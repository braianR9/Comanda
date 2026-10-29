using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Npgsql;

namespace BarIceCreamShop.Api.Security;

public static class SystemsSetup
{
    public static void SaveOwner(string email, string password)
    {
        var path = Path.Combine(Directory.GetCurrentDirectory(), "src", "appsettings.Local.json");
        var root = File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path))!.AsObject() : new JsonObject();
        root["SystemsOwner"] = new JsonObject { ["Email"] = email.Trim().ToLowerInvariant(),
            ["PasswordHash"] = BCrypt.Net.BCrypt.HashPassword(password, workFactor: 12) };
        WritePrivate(path, root.ToJsonString(new() { WriteIndented = true }));
    }

    public static void WritePrivate(string path, string content)
    {
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            var options = new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write };
            if (!OperatingSystem.IsWindows()) options.UnixCreateMode = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            using (var stream = new FileStream(temp, options))
            using (var writer = new StreamWriter(stream)) writer.Write(content);
            File.Move(temp, path, overwrite: true);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    public static async Task Run(IConfiguration config, string[] args)
    {
        if (!string.IsNullOrWhiteSpace(config["SystemsOwner:PasswordHash"]) && !args.Contains("--reset-owner"))
            throw new InvalidOperationException("Ya existe un propietario. Para cambiarlo usá --reset-owner.");
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("SystemsOwner__PasswordHash")))
            throw new InvalidOperationException("El propietario está configurado por variables de entorno. Actualizalas en el servidor.");
        var index = Array.IndexOf(args, "--email");
        var email = index >= 0 && index + 1 < args.Length ? args[index + 1] : config["SystemsOwner:Email"];
        if (string.IsNullOrWhiteSpace(email)) { Console.Write("Correo del propietario: "); email = Console.ReadLine(); }
        if (!new System.ComponentModel.DataAnnotations.EmailAddressAttribute().IsValid(email))
            throw new InvalidOperationException("Indicá un correo válido.");
        await using var connection = new NpgsqlConnection(config.GetConnectionString("DefaultConnection"));
        await connection.OpenAsync();
        await using var check = new NpgsqlCommand("SELECT to_regclass('public.sistemas_eventos') IS NOT NULL", connection);
        if (!(bool)(await check.ExecuteScalarAsync())!)
            throw new InvalidOperationException("Primero ejecutá database/add_systems_admin.sql como propietario de la base (postgres). Luego repetí este comando.");
        string password;
        if (args.Contains("--generate-password")) password = Convert.ToBase64String(RandomNumberGenerator.GetBytes(24));
        else
        {
            Console.Write("Contraseña (mínimo 12 caracteres): "); password = ReadPassword();
            Console.Write("Repetir contraseña: ");
            if (ReadPassword() != password) throw new InvalidOperationException("Las contraseñas no coinciden.");
        }
        if (password.Length < 12 || System.Text.Encoding.UTF8.GetByteCount(password) > 72)
            throw new InvalidOperationException("Usá entre 12 caracteres y 72 bytes para la contraseña.");
        SaveOwner(email!, password);
        if (args.Contains("--generate-password"))
        {
            var credentials = Path.Combine(Directory.GetCurrentDirectory(), ".systems-owner-credentials.txt");
            WritePrivate(credentials, $"Acceso de sistemas de focobr\nCorreo: {email}\nContraseña: {password}\n\nGuardá esta contraseña y borrá este archivo. No lo publiques ni lo subas al repositorio.\n");
            Console.WriteLine("Credenciales guardadas en .systems-owner-credentials.txt (archivo privado, excluido de Git).");
        }
        Console.WriteLine("Panel de sistemas configurado. Reiniciá la API si estaba en ejecución.");
    }

    private static string ReadPassword()
    {
        var value = new System.Text.StringBuilder();
        while (true)
        {
            var key = Console.ReadKey(intercept: true);
            if (key.Key == ConsoleKey.Enter) { Console.WriteLine(); return value.ToString(); }
            if (key.Key == ConsoleKey.Backspace) { if (value.Length > 0) value.Length--; }
            else if (!char.IsControl(key.KeyChar)) value.Append(key.KeyChar);
        }
    }
}
