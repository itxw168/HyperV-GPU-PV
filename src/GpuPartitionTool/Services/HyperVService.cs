using System.Text.Json;

namespace GpuPartitionTool.Services;

/// <summary>只读查询：枚举虚拟机、可分区 GPU（调用 info.ps1，不产生任何副作用）</summary>
public class HyperVService
{
    public async Task<(List<VmInfo> Vms, List<GpuInfo> Gpus, string Message, bool HyperVEnabled)> GetEnvironmentInfo(Action<string> log)
    {
        return await Task.Run(() =>
        {
            var r = PowerShellRunner.Run("info.ps1", null, log, timeoutSeconds: 90);
            var vms = new List<VmInfo>();
            var gpus = new List<GpuInfo>();
            var hypervEnabled = true;

            if (r.Ok && !string.IsNullOrEmpty(r.RawJson))
            {
                try
                {
                    using var doc = JsonDocument.Parse(r.RawJson);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("data", out var data))
                    {
                        if (data.TryGetProperty("hypervEnabled", out var he))
                            hypervEnabled = he.GetBoolean();
                        if (data.TryGetProperty("vms", out var vmsEl))
                        {
                            foreach (var v in vmsEl.EnumerateArray())
                            {
                                vms.Add(new VmInfo
                                {
                                    Name = v.GetProperty("name").GetString() ?? "",
                                    State = v.GetProperty("state").GetString() ?? "",
                                    MemoryAssignedMB = v.GetProperty("memoryAssignedMB").GetInt64(),
                                    ProcessorCount = v.GetProperty("processorCount").GetInt32()
                                });
                            }
                        }
                        if (data.TryGetProperty("gpus", out var gpusEl))
                        {
                            foreach (var g in gpusEl.EnumerateArray())
                            {
                                gpus.Add(new GpuInfo
                                {
                                    InstanceId = g.GetProperty("instanceId").GetString() ?? "",
                                    Vendor = g.GetProperty("vendor").GetString() ?? "",
                                    Name = g.GetProperty("name").GetString() ?? "",
                                    Status = g.GetProperty("status").GetString() ?? "",
                                    IsPartitionable = g.TryGetProperty("isPartitionable", out var ip) && ip.GetBoolean(),
                                    TotalVRAM = g.GetProperty("totalVRAM").GetInt64(),
                                    PhysicalVRAM = g.TryGetProperty("physicalVRAM", out var pv) && pv.GetInt64() > 0 ? pv.GetInt64() : 0,
                                    TotalCompute = g.GetProperty("totalCompute").GetInt64(),
                                    TotalDecode = g.GetProperty("totalDecode").GetInt64(),
                                    TotalEncode = g.GetProperty("totalEncode").GetInt64()
                                });
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    return (vms, gpus, "解析虚拟机/GPU 信息失败：" + ex.Message, hypervEnabled);
                }
            }

            return (vms, gpus, r.Message, hypervEnabled);
        });
    }
}
