using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly: AssemblyTitle("OneClick UNIVAP")]
[assembly: AssemblyDescription("Preparação do laboratório Arduino, ESP32 e RP2040")]
[assembly: AssemblyVersion("1.0.0.0")]

internal static class Program
{
    internal static string ExtractScript()
    {
        string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OneClick-UNIVAP", "launcher", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "install.ps1");
        using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("OneClick.install.ps1"))
        {
            if (resource == null) throw new InvalidOperationException("Recurso install.ps1 ausente.");
            using (FileStream file = File.Create(path)) resource.CopyTo(file);
        }
        return path;
    }

    internal static ProcessStartInfo PowerShell(string script, string options)
    {
        return new ProcessStartInfo {
            FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"),
            Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\" " + options,
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        };
    }

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
        {
            string script = null;
            try {
                script = ExtractScript();
                using (Process p = new Process { StartInfo = PowerShell(script, "-SelfTest") }) {
                    p.Start();
                    Task<string> stdout = p.StandardOutput.ReadToEndAsync();
                    Task<string> stderr = p.StandardError.ReadToEndAsync();
                    p.WaitForExit();
                    Task.WaitAll(stdout, stderr);
                    Console.Write(stdout.Result); Console.Error.Write(stderr.Result);
                    return p.ExitCode;
                }
            } catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
            finally { if (script != null) try { Directory.Delete(Path.GetDirectoryName(script), true); } catch { } }
        }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new InstallerForm());
        return 0;
    }
}

internal sealed class InstallerForm : Form
{
    private readonly Color Navy = Color.FromArgb(0, 59, 113);
    private readonly Color Red = Color.FromArgb(218, 41, 28);
    private readonly CheckedListBox choices = new CheckedListBox();
    private readonly TextBox log = new TextBox();
    private readonly Button install = new Button();
    private readonly ProgressBar progress = new ProgressBar();
    private readonly Label status = new Label();
    private bool running;
    private readonly string[] ids = { "ide", "cli", "esp32", "pico", "mbed", "cp210x", "ch340", "ftdi", "libraries" };

    internal InstallerForm()
    {
        Text = "OneClick | Laboratório UNIVAP";
        Size = new Size(880, 790); MinimumSize = new Size(760, 720);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10); BackColor = Color.White;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 8, Padding = new Padding(24) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        foreach (int height in new int[] { 63, 68, 222, 39, 30, 28 }) layout.RowStyles.Add(new RowStyle(SizeType.Absolute, height));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 35));
        Controls.Add(layout);
        var heading = new Label { Text = "ONECLICK  /  LABORATÓRIO 2027", Font = new Font("Segoe UI", 21, FontStyle.Bold), ForeColor = Navy, Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft };
        layout.Controls.Add(heading, 0, 0);
        layout.Controls.Add(new Label { Text = "Arduino, ESP32 e Raspberry Pi Pico em um só instalador.\nFeche o Arduino IDE. Será necessária internet e a instalação ocorrerá na conta Windows que executar este programa.", Dock = DockStyle.Fill, ForeColor = Color.FromArgb(50, 60, 75) }, 0, 1);
        choices.Dock = DockStyle.Fill; choices.CheckOnClick = true; choices.BorderStyle = BorderStyle.None; choices.IntegralHeight = false;
        foreach (string label in new string[] { "Arduino IDE — versão estável mais recente", "Arduino CLI — versão estável mais recente", "Placas ESP32 (Espressif)", "Placas RP2040 / Pico (Earle Philhower)", "Placas Arduino Mbed RP2040", "Driver USB Silicon Labs CP210x", "Driver USB WCH CH340 / CH341", "Driver USB FTDI", "Bibliotecas didáticas: DHT, Adafruit Sensor, MQTT, JSON, LCD I2C e Servo" }) choices.Items.Add(label, true);
        layout.Controls.Add(choices, 0, 2);
        install.Text = "Instalar selecionados"; install.Dock = DockStyle.Fill; install.BackColor = Red; install.ForeColor = Color.White; install.FlatStyle = FlatStyle.Flat; install.FlatAppearance.BorderSize = 0; install.Cursor = Cursors.Hand;
        install.Click += async delegate { await InstallAsync(); };
        layout.Controls.Add(install, 0, 3);
        status.Text = "Pronto. Você pode escolher os componentes acima."; status.Dock = DockStyle.Fill; status.TextAlign = ContentAlignment.MiddleLeft; status.ForeColor = Navy;
        layout.Controls.Add(status, 0, 4);
        progress.Dock = DockStyle.Fill; layout.Controls.Add(progress, 0, 5);
        log.Multiline = true; log.ReadOnly = true; log.ScrollBars = ScrollBars.Both; log.WordWrap = false; log.Dock = DockStyle.Fill; log.Font = new Font("Consolas", 9); log.BackColor = Color.FromArgb(242, 246, 251); log.BorderStyle = BorderStyle.FixedSingle;
        layout.Controls.Add(log, 0, 6);
        var footer = new LinkLabel { Text = "Abrir pasta de logs e resultados", Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleLeft, LinkColor = Navy };
        footer.LinkClicked += delegate { string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OneClick-UNIVAP"); Directory.CreateDirectory(dir); Process.Start("explorer.exe", "\"" + dir + "\""); };
        layout.Controls.Add(footer, 0, 7);
        FormClosing += delegate(object sender, FormClosingEventArgs e) { if (running) { e.Cancel = true; MessageBox.Show(this, "A instalação ainda está em andamento. Aguarde o resultado antes de fechar.", "Instalação em andamento", MessageBoxButtons.OK, MessageBoxIcon.Information); } };
    }

    private void Append(string line)
    {
        if (line == null || IsDisposed) return;
        if (InvokeRequired) { BeginInvoke(new Action<string>(Append), line); return; }
        if (line.StartsWith("@@PROGRESS:")) { int value; if (int.TryParse(line.Substring(11), out value)) progress.Value = Math.Max(0, Math.Min(100, value)); return; }
        log.AppendText(line + Environment.NewLine);
    }

    private async Task InstallAsync()
    {
        if (running) return;
        var selected = new List<string>();
        foreach (int index in choices.CheckedIndices) selected.Add(ids[index]);
        if (selected.Count == 0) { status.Text = "Selecione pelo menos um componente."; return; }
        running = true; choices.Enabled = false; install.Enabled = false; progress.Value = 0; log.Clear();
        status.Text = "Instalando… consulte o progresso detalhado abaixo.";
        string script = null;
        try {
            script = Program.ExtractScript();
            int result = await Task.Run(delegate {
                using (Process p = new Process { StartInfo = Program.PowerShell(script, "-Components " + string.Join(",", selected.ToArray())) }) {
                    p.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e) { Append(e.Data); };
                    p.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e) { Append(e.Data); };
                    p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine(); p.WaitForExit();
                    return p.ExitCode;
                }
            });
            status.Text = result == 0 ? "Concluído. Os componentes selecionados foram instalados." : "Há falhas. Consulte o log e selecione os itens para tentar novamente.";
            status.ForeColor = result == 0 ? Navy : Red;
        } catch (Exception ex) { Append("ERRO: " + ex.Message); status.Text = "Não foi possível concluir. Consulte o log."; status.ForeColor = Red; }
        finally {
            if (script != null) try { Directory.Delete(Path.GetDirectoryName(script), true); } catch { }
            running = false; choices.Enabled = true; install.Enabled = true; install.Text = "Instalar / tentar novamente";
        }
    }
}
