using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;
using GpuPartitionTool.Services;

namespace GpuPartitionTool;

public partial class MainWindow : Window
{
    private readonly HyperVService _hyperV = new();
    private readonly DeployService _deploy = new();
    private bool _busy;
    private string? _lastVmName;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += MainWindow_Loaded;
    }

    private void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        AppendLog("软件已启动（管理员权限已确认）。");
        AppendLog("正在检测 Hyper-V 环境与可分区显卡...");
        _ = RefreshAsync();
    }

    // ---------- 刷新：枚举虚拟机与显卡 ----------
    private async Task RefreshAsync()
    {
        SetBusy(true);
        try
        {
            var (vms, gpus, msg, hypervEnabled) = await _hyperV.GetEnvironmentInfo(s => AppendLog(s));
            VmGrid.ItemsSource = vms;
            GpuGrid.ItemsSource = gpus;
            // Hyper-V 未启用时显示提示条（含「一键开启 Hyper-V」按钮）
            HyperVTipBar.Visibility = hypervEnabled ? Visibility.Collapsed : Visibility.Visible;

            // 恢复之前的选中（显卡自动选第一个可分配显卡；虚拟机恢复上次选择，否则选第一台）
            if (gpus.Count > 0)
            {
                GpuGrid.SelectedItem = gpus.FirstOrDefault(g => g.IsPartitionable) ?? gpus[0];
            }
            if (vms.Count > 0)
            {
                VmGrid.SelectedItem = !string.IsNullOrEmpty(_lastVmName)
                    ? vms.FirstOrDefault(v => v.Name == _lastVmName) ?? vms[0]
                    : vms[0];
            }

            if (!hypervEnabled)
            {
                AppendLog("未检测到 Hyper-V 功能（vmms 服务未运行）。可点击上方「一键开启 Hyper-V」自动安装并开启。", true);
            }
            else
            {
                AppendLog($"检测完成：发现 {vms.Count} 台虚拟机，{gpus.Count} 个可分区显卡。");
                if (gpus.Count == 0)
                    AppendLog("未检测到可分区 GPU（显卡可能不支持 GPU-PV 或驱动未就绪）。", true);
                if (vms.Count == 0)
                    AppendLog("未发现任何虚拟机。", true);
                if (msg != "OK")
                    AppendLog("检测异常：" + msg, true);
            }
            UpdateButtons();
        }
        catch (Exception ex)
        {
            AppendLog("刷新失败：" + ex.Message, true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        AppendLog("正在刷新...");
        _ = RefreshAsync();
    }

    // ---------- 选中虚拟机 / 比例滑块 ----------
    private void VmGrid_SelectionChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        var vm = VmGrid.SelectedItem as VmInfo;
        _lastVmName = vm?.Name;
        TargetText.Text = vm != null
            ? $"目标虚拟机：{vm.Name}"
            : "目标虚拟机：未选择";

        // 选中虚拟机后徽章白底绿字，提示目标已就绪
        if (vm != null)
        {
            TargetBadge.Background = Brushes.White;
            TargetBadge.BorderBrush = new SolidColorBrush(Color.FromRgb(34, 197, 94));      // #22C55E 绿色边框
            TargetText.Foreground = new SolidColorBrush(Color.FromRgb(22, 163, 74));        // #16A34A 绿色文字
        }
        else
        {
            TargetBadge.Background = new SolidColorBrush(Color.FromRgb(51, 65, 85));       // #334155
            TargetBadge.BorderBrush = new SolidColorBrush(Color.FromRgb(51, 65, 85));
            TargetText.Foreground = Brushes.White;
        }
        UpdateButtons();
    }

    private void ShareSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        var value = Math.Round(ShareSlider.Value / 0.05) * 0.05;
        SharePercentText.Text = $"{Math.Round(value * 100)}%";
    }

    // ---------- 部署 ----------
    private async void DeployButton_Click(object sender, RoutedEventArgs e)
    {
        if (VmGrid.SelectedItem is not VmInfo vm) return;
        if (GpuGrid.SelectedItem is not GpuInfo gpu || !gpu.IsPartitionable)
        {
            AppendLog("请先选择一台「可分配」的显卡。", true);
            return;
        }

        var share = Math.Round(ShareSlider.Value / 0.05) * 0.05;
        if (share <= 0 || share > 1)
        {
            AppendLog("分配比例无效。", true);
            return;
        }

        var confirm = MessageBox.Show(
            $"将为目标虚拟机「{vm.Name}」配置 GPU 分区（{gpu.Vendor} {gpu.Name}，分配 {Math.Round(share * 100)}%）。\n\n" +
            "配置过程中会关闭并重启该虚拟机。确认继续？",
            "确认部署", MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (confirm != MessageBoxResult.OK) return;

        SetBusy(true);
        AppendLog($"===== 开始部署：虚拟机「{vm.Name}」 分配 {Math.Round(share * 100)}% =====");
        try
        {
            var r = await _deploy.Deploy(vm, gpu, share, s => AppendLog(s));
            AppendLog(r.Ok ? "✓ " + r.Message : "✗ " + r.Message, !r.Ok);
            MessageBox.Show(r.Message, r.Ok ? "部署完成" : "部署失败",
                MessageBoxButton.OK, r.Ok ? MessageBoxImage.Information : MessageBoxImage.Error);
        }
        catch (Exception ex)
        {
            AppendLog("部署异常：" + ex.Message, true);
        }
        finally
        {
            SetBusy(false);
            await RefreshAsync();
        }
    }

    // ---------- 卸载 ----------
    private async void UninstallButton_Click(object sender, RoutedEventArgs e)
    {
        if (VmGrid.SelectedItem is not VmInfo vm) return;

        var confirm = MessageBox.Show(
            $"将移除虚拟机「{vm.Name}」的 GPU 分区并恢复 MMIO 设置。\n\n" +
            "配置过程中会关闭该虚拟机。确认继续？",
            "确认卸载", MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (confirm != MessageBoxResult.OK) return;

        SetBusy(true);
        AppendLog($"===== 开始卸载：虚拟机「{vm.Name}」 =====");
        try
        {
            var r = await _deploy.Uninstall(vm.Name, s => AppendLog(s));
            AppendLog(r.Ok ? "✓ " + r.Message : "✗ " + r.Message, !r.Ok);
            MessageBox.Show(r.Message, r.Ok ? "卸载完成" : "卸载失败",
                MessageBoxButton.OK, r.Ok ? MessageBoxImage.Information : MessageBoxImage.Error);
        }
        catch (Exception ex)
        {
            AppendLog("卸载异常：" + ex.Message, true);
        }
        finally
        {
            SetBusy(false);
            await RefreshAsync();
        }
    }

    // ---------- 新建虚拟机 ----------
    private async void NewVmButton_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new CreateVmWindow { Owner = this };
        dlg.ShowDialog();
        if (!dlg.Confirmed) return;

        SetBusy(true);
        AppendLog($"===== 开始创建虚拟机「{dlg.VmName}」 =====");
        try
        {
            var r = await _deploy.CreateVm(dlg.VmName, dlg.MemGB, dlg.Cpu, dlg.DiskGB, dlg.Iso, s => AppendLog(s));
            AppendLog(r.Ok ? "✓ " + r.Message : "✗ " + r.Message, !r.Ok);
            MessageBox.Show(r.Message, r.Ok ? "创建完成" : "创建失败",
                MessageBoxButton.OK, r.Ok ? MessageBoxImage.Information : MessageBoxImage.Error);
        }
        catch (Exception ex)
        {
            AppendLog("创建异常：" + ex.Message, true);
        }
        finally
        {
            SetBusy(false);
            await RefreshAsync();
        }
    }

    // ---------- 导入 D:\Hyper-v 中未注册的虚拟机 ----------
    private async void ImportVmButton_Click(object sender, RoutedEventArgs e)
    {
        SetBusy(true);
        AppendLog(@"===== 扫描 D:\Hyper-v 导入虚拟机 =====");
        try
        {
            var r = await _deploy.ImportVms(s => AppendLog(s));
            AppendLog(r.Ok ? "✓ " + r.Message : "✗ " + r.Message, !r.Ok);
            MessageBox.Show(r.Message, r.Ok ? "导入完成" : "导入失败",
                MessageBoxButton.OK, r.Ok ? MessageBoxImage.Information : MessageBoxImage.Error);
        }
        catch (Exception ex)
        {
            AppendLog("导入异常：" + ex.Message, true);
        }
        finally
        {
            SetBusy(false);
            await RefreshAsync();
        }
    }

    // ---------- 一键开启 Hyper-V ----------
    private async void EnableHyperVButton_Click(object sender, RoutedEventArgs e)
    {
        var confirm = MessageBox.Show(
            "将自动启用 Hyper-V 功能（Windows 家庭版将使用兼容方式安装 Hyper-V 组件包）。\n\n" +
            "完成后需要重启电脑才能生效。确认继续？",
            "确认开启 Hyper-V", MessageBoxButton.OKCancel, MessageBoxImage.Question);
        if (confirm != MessageBoxResult.OK) return;

        SetBusy(true);
        AppendLog("===== 开始开启 Hyper-V =====");
        try
        {
            var r = await _deploy.EnableHyperV(s => AppendLog(s));
            AppendLog(r.Ok ? "✓ " + r.Message : "✗ " + r.Message, !r.Ok);
            MessageBox.Show(r.Message, r.Ok ? "开启完成" : "开启失败",
                MessageBoxButton.OK, r.Ok ? MessageBoxImage.Information : MessageBoxImage.Error);
        }
        catch (Exception ex)
        {
            AppendLog("开启异常：" + ex.Message, true);
        }
        finally
        {
            SetBusy(false);
            await RefreshAsync();
        }
    }

    // ---------- 状态控制 ----------
    private void UpdateButtons()
    {
        var hasVm = VmGrid.SelectedItem is VmInfo;
        var hasGpu = GpuGrid.SelectedItem is GpuInfo g && g.IsPartitionable;
        DeployButton.IsEnabled = !_busy && hasVm && hasGpu;
        UninstallButton.IsEnabled = !_busy && hasVm;
    }

    private void SetBusy(bool busy)
    {
        _busy = busy;
        RefreshButton.IsEnabled = !busy;
        UpdateButtons();
    }

    private void AppendLog(string text, bool isError = false)
    {
        Dispatcher.Invoke(() =>
        {
            // 纯文本追加日志（白色文字，渲染清晰无空行问题）
            LogBox.AppendText($"[{DateTime.Now:HH:mm:ss}] {text}{Environment.NewLine}");
            LogBox.ScrollToEnd();
        });
    }
}
