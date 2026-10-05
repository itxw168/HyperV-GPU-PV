namespace GpuPartitionTool;

/// <summary>Hyper-V 虚拟机信息</summary>
public class VmInfo
{
    public string Name { get; set; } = "";
    public string State { get; set; } = "";
    public long MemoryAssignedMB { get; set; }
    public int ProcessorCount { get; set; }

    public string MemoryDisplay => MemoryAssignedMB <= 0 ? "-" : $"{MemoryAssignedMB / 1024.0:0.#} GB";
    public string StateDisplay => State switch
    {
        "Running" => "运行中",
        "Off" => "已关闭",
        "Saved" => "已保存",
        _ => State
    };
}

/// <summary>宿主机可分区 GPU 信息</summary>
public class GpuInfo
{
    public string InstanceId { get; set; } = "";
    public string Vendor { get; set; } = "";
    public string Name { get; set; } = "";
    public string Status { get; set; } = "";
    public bool IsPartitionable { get; set; }
    public long TotalVRAM { get; set; }
    public long PhysicalVRAM { get; set; }
    public long TotalCompute { get; set; }
    public long TotalDecode { get; set; }
    public long TotalEncode { get; set; }

    public string DisplayName => string.IsNullOrWhiteSpace(Name) ? Vendor : Name;
    public string PartText => IsPartitionable ? "可分配" : "不可分配";
    public string VramDisplay
    {
        get
        {
            // 优先显示物理显存（注册表读取），回退 GPU-P 配额值
            var v = PhysicalVRAM > 0 ? PhysicalVRAM : TotalVRAM;
            return v <= 0 ? "-" : $"{v / 1024.0 / 1024.0 / 1024.0:0.#} GB";
        }
    }

    /// <summary>紧凑显示名（去掉品牌冗余词，用于窄下拉框）</summary>
    public string ShortName
    {
        get
        {
            var n = Name;
            foreach (var w in new[] { "Radeon", "GeForce", "Intel(R)", "UHD Graphics", "Graphics", "UHD", "Integrated" })
                n = n.Replace(w, "").Trim();
            return string.IsNullOrWhiteSpace(n) ? Vendor : n.Trim();
        }
    }
}

/// <summary>PowerShell 脚本执行结果</summary>
public class PsResult
{
    public bool Ok { get; set; }
    public string Message { get; set; } = "";
    public string RawJson { get; set; } = "";
}
