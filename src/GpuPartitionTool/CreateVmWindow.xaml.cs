using System.IO;
using System.Windows;
using Microsoft.Win32;

namespace GpuPartitionTool;

public partial class CreateVmWindow : Window
{
    /// <summary>创建参数（点击创建后有效）</summary>
    public string VmName = "";
    public int MemGB = 8;
    public int Cpu = 4;
    public int DiskGB = 80;
    public string Iso = "";
    public bool Confirmed;

    public CreateVmWindow()
    {
        InitializeComponent();
    }

    private void BrowseButton_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "选择系统安装镜像",
            Filter = "系统镜像 (*.iso)|*.iso|所有文件 (*.*)|*.*"
        };
        if (dlg.ShowDialog(this) == true)
            IsoBox.Text = dlg.FileName;
    }

    private void CreateButton_Click(object sender, RoutedEventArgs e)
    {
        VmName = NameBox.Text.Trim();
        if (string.IsNullOrEmpty(VmName))
        {
            MessageBox.Show(this, "请填写虚拟机名称。", "提示", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!int.TryParse(MemBox.Text.Trim(), out MemGB) || MemGB < 1)
        {
            MessageBox.Show(this, "内存请填写正整数（GB）。", "提示", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!int.TryParse(CpuBox.Text.Trim(), out Cpu) || Cpu < 1)
        {
            MessageBox.Show(this, "CPU 核数请填写正整数。", "提示", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (!int.TryParse(DiskBox.Text.Trim(), out DiskGB) || DiskGB < 20)
        {
            MessageBox.Show(this, "磁盘大小至少 20GB。", "提示", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        Iso = File.Exists(IsoBox.Text.Trim()) ? IsoBox.Text.Trim() : "";
        Confirmed = true;
        Close();
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        Confirmed = false;
        Close();
    }
}
