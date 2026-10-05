using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;

namespace GpuPartitionTool.Services;

/// <summary>
/// 以管理员权限启动 powershell.exe（Windows PowerShell 5.1，自带 Hyper-V 模块）执行脚本。
/// 脚本约定：普通行走 stdout 转发为日志；最终一行以 #JSON# 开头输出结果 JSON。
/// 参数通过环境变量传递（避免命令行特殊字符转义问题，尤其密码）。
/// </summary>
public static class PowerShellRunner
{
    public static PsResult Run(string scriptName, Dictionary<string, string>? env = null,
        Action<string>? logLine = null, int timeoutSeconds = 600)
    {
        var scriptPath = ResolveScriptPath(scriptName);
        if (!File.Exists(scriptPath))
        {
            return new PsResult { Ok = false, Message = $"找不到脚本文件：{scriptPath}" };
        }

        var psi = new ProcessStartInfo
        {
            FileName = Path.Combine(Environment.SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe"),
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };

        if (env != null)
        {
            foreach (var kv in env)
                psi.Environment[kv.Key] = kv.Value;
        }

        var jsonLine = "";
        var lastErr = new StringBuilder();

        using var proc = new Process { StartInfo = psi };
        proc.OutputDataReceived += (_, e) =>
        {
            if (string.IsNullOrEmpty(e.Data)) return;
            if (e.Data.StartsWith("#JSON#"))
                jsonLine = e.Data[6..];
            else
                logLine?.Invoke(e.Data);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (string.IsNullOrEmpty(e.Data)) return;
            if (e.Data.StartsWith("#JSON#"))
                jsonLine = e.Data[6..];
            else
            {
                lastErr.AppendLine(e.Data);
                logLine?.Invoke("[错误] " + e.Data);
            }
        };

        try
        {
            proc.Start();
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
        }
        catch (Exception ex)
        {
            return new PsResult { Ok = false, Message = "启动 PowerShell 失败：" + ex.Message };
        }

        if (!proc.WaitForExit(timeoutSeconds * 1000))
        {
            try { proc.Kill(true); } catch { }
            return new PsResult
            {
                Ok = false,
                Message = $"操作超时（{timeoutSeconds} 秒），虚拟机可能处于中间状态，请用「卸载」功能清理。"
            };
        }
        proc.WaitForExit();
        var exitCode = proc.ExitCode;

        if (!string.IsNullOrWhiteSpace(jsonLine))
        {
            try
            {
                using var doc = JsonDocument.Parse(jsonLine);
                var root = doc.RootElement;
                var ok = root.TryGetProperty("ok", out var okEl) && okEl.GetBoolean();
                var msg = root.TryGetProperty("message", out var msgEl) ? msgEl.GetString() ?? "" : "";
                return new PsResult { Ok = ok, Message = msg, RawJson = jsonLine };
            }
            catch (Exception ex)
            {
                return new PsResult { Ok = false, Message = "脚本输出解析失败：" + ex.Message };
            }
        }

        return new PsResult
        {
            Ok = exitCode == 0,
            Message = exitCode == 0
                ? "脚本执行完成（无结果输出）"
                : $"脚本执行失败，退出码 {exitCode}。" +
                  (lastErr.Length > 0 ? " 最后输出：" + lastErr.ToString().Trim() : "")
        };
    }

    /// <summary>
    /// 解析脚本路径：优先用 exe 旁的 Scripts 目录；否则每次从程序集内嵌资源重新释放到临时目录，
    /// 保证脚本始终与当前程序版本一致（避免复用旧版脚本导致字段不匹配）。
    /// </summary>
    private static string ResolveScriptPath(string scriptName)
    {
        var beside = Path.Combine(AppContext.BaseDirectory, "Scripts", scriptName);
        if (File.Exists(beside)) return beside;

        var dir = Path.Combine(Path.GetTempPath(), "GpuPartitionTool", "Scripts");
        var path = Path.Combine(dir, scriptName);

        var resourceName = $"GpuPartitionTool.Scripts.{scriptName}";
        using var stream = typeof(PowerShellRunner).Assembly.GetManifestResourceStream(resourceName);
        if (stream == null) return path;

        Directory.CreateDirectory(dir);
        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        File.WriteAllBytes(path, ms.ToArray()); // 覆盖旧版本
        return path;
    }
}
