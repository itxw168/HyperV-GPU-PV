using System.Security.Principal;
using System.Windows;
using System.Windows.Threading;

namespace GpuPartitionTool;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 管理员身份校验（manifest 已声明 requireAdministrator，此处兜底）
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        if (!principal.IsInRole(WindowsBuiltInRole.Administrator))
        {
            MessageBox.Show("本工具需要以管理员身份运行。\n请右键程序图标，选择「以管理员身份运行」。",
                "需要管理员权限", MessageBoxButton.OK, MessageBoxImage.Warning);
            Shutdown();
            return;
        }

        DispatcherUnhandledException += (_, args) =>
        {
            MessageBox.Show("发生未处理的异常：" + args.Exception.Message,
                "错误", MessageBoxButton.OK, MessageBoxImage.Error);
            args.Handled = true;
        };
    }
}
