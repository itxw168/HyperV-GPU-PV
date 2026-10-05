using System.Globalization;

namespace GpuPartitionTool.Services;

/// <summary>部署 / 卸载流程驱动：拼环境变量参数 → 调用 deploy.ps1 / uninstall.ps1 → 转发日志与结果</summary>
public class DeployService
{
    public async Task<PsResult> Deploy(VmInfo vm, GpuInfo gpu, double share, Action<string> log)
    {
        return await Task.Run(() =>
        {
            var env = new Dictionary<string, string>
            {
                ["GPTOOL_VMNAME"] = vm.Name,
                ["GPTOOL_GPUINSTANCE"] = gpu.InstanceId,
                ["GPTOOL_SHARE"] = share.ToString("0.00", CultureInfo.InvariantCulture)
            };
            return PowerShellRunner.Run("deploy.ps1", env, log, timeoutSeconds: 900);
        });
    }

    public async Task<PsResult> Uninstall(string vmName, Action<string> log)
    {
        return await Task.Run(() =>
        {
            var env = new Dictionary<string, string> { ["GPTOOL_VMNAME"] = vmName };
            return PowerShellRunner.Run("uninstall.ps1", env, log, timeoutSeconds: 300);
        });
    }

    /// <summary>一键开启 Hyper-V 功能（家庭版/专业版兼容，需重启生效）</summary>
    public async Task<PsResult> EnableHyperV(Action<string> log)
    {
        return await Task.Run(() =>
            PowerShellRunner.Run("enable-hyperv.ps1", null, log, timeoutSeconds: 900));
    }

    /// <summary>一键创建虚拟机（存储于 D:\Hyper-v，增强会话默认开启）</summary>
    public async Task<PsResult> CreateVm(string name, int memGB, int cpu, int diskGB, string iso, Action<string> log)
    {
        return await Task.Run(() =>
        {
            var env = new Dictionary<string, string>
            {
                ["GPTOOL_NEWVM_NAME"] = name,
                ["GPTOOL_NEWVM_MEM"] = memGB.ToString(),
                ["GPTOOL_NEWVM_CPU"] = cpu.ToString(),
                ["GPTOOL_NEWVM_DISK"] = diskGB.ToString(),
                ["GPTOOL_NEWVM_ISO"] = iso
            };
            return PowerShellRunner.Run("create-vm.ps1", env, log, timeoutSeconds: 300);
        });
    }

    /// <summary>扫描 D:\Hyper-v 导入新虚拟机（已注册的跳过）</summary>
    public async Task<PsResult> ImportVms(Action<string>? log = null)
    {
        return await Task.Run(() =>
            PowerShellRunner.Run("import-vm.ps1", null, log, timeoutSeconds: 180));
    }
}
