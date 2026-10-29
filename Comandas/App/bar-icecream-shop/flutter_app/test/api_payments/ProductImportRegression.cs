using BarIceCreamShop.Api.Controllers;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using BarIceCreamShop.Api.Services;
using ClosedXML.Excel;

static class ProductImportRegression
{
    public static void Run(string? path)
    {
        void Check(bool value, string message) { if (!value) throw new Exception(message); Console.WriteLine("PASS: " + message); }
        using var book = new XLWorkbook();
        var sheet = book.AddWorksheet("Productos");
        sheet.Cell(2, 1).Value = "Productos";
        var headers = new[] { "Código", "Nombre", "Costo", "Precio", "Rubro", "Subrubro", "Alicuota", "Activo" };
        for (int i = 0; i < headers.Length; i++) sheet.Cell(5, i + 1).Value = headers[i];
        sheet.Cell(6, 1).Value = "S01";
        sheet.Cell(6, 2).Value = " Chocolate ";
        sheet.Cell(6, 3).Value = 0;
        sheet.Cell(6, 4).Value = 0;
        sheet.Cell(6, 5).Value = "Sabores";
        sheet.Cell(6, 6).Value = "Sabores";
        sheet.Cell(6, 7).Value = 21;
        sheet.Cell(6, 8).Value = 1;
        using var savedStream = new MemoryStream();
        ProductImportResult Parse() { book.SaveAs(savedStream); using var input = new MemoryStream(savedStream.ToArray()); return ProductoService.ReadProductWorkbook(input); }
        var parsed = Parse();
        Check(parsed.PuedeImportar && parsed.Filas.Single().Codigo == "S01", "Detect export header and preserve alphanumeric code");
        Check(parsed.Filas[0].Nombre == "Chocolate" && parsed.Filas[0].Advertencias.Count == 1, "Trim text and flag zero prices without rejecting flavors");
        sheet.Cell(6, 4).Value = "1250,50";
        Check(Parse().Filas[0].Precio == 1250.50m, "Parse Argentine decimal text");
        sheet.Cell(6, 4).Value = -1;
        Check(!Parse().PuedeImportar, "Reject negative price");
        sheet.Cell(6, 4).Value = "incorrecto";
        Check(!Parse().PuedeImportar, "Reject invalid numeric value");
        sheet.Cell(6, 4).Value = 100;
        sheet.Cell(6, 8).Value = "quizás";
        Check(!Parse().PuedeImportar, "Reject invalid active flag");
        sheet.Cell(6, 8).Value = 0;
        Check(!Parse().Filas[0].Activo, "Preserve inactive status");
        for (int i = 1; i <= headers.Length; i++) sheet.Cell(7, i).Value = sheet.Cell(6, i).Value;
        Check(Parse().Filas[1].Errores.Count >= 2, "Reject repeated names and codes within workbook");
        sheet.Cell(5, 4).Value = "Otro";
        try { Parse(); throw new Exception("Missing header accepted"); }
        catch (ProductoException) { Console.WriteLine("PASS: Reject missing required column"); }
        // Invalid workbook: progress must arrive before the error, without a result
        // event claiming success. This path never reaches the database.
        using var services = new ServiceCollection().AddLogging().BuildServiceProvider();
        using var response = new MemoryStream();
        var http = new DefaultHttpContext { RequestServices = services,
            User = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("id_empresa", "1"), new Claim("id_sucursal", "1")])) };
        http.Response.Body = response;
        var controller = new ProductosController(new ProductoService(null!, null!), null!) {
            ControllerContext = new() { HttpContext = http }
        };
        using var badWorkbook = new MemoryStream("invalid workbook"u8.ToArray());
        controller.Import(new FormFile(badWorkbook, 0, badWorkbook.Length, "archivo", "productos.xlsx"),
            confirmar: false, progreso: true).GetAwaiter().GetResult();
        var events = Encoding.UTF8.GetString(response.ToArray()).Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Select(line => JsonDocument.Parse(line)).ToList();
        Check(events.Count == 2 && events[0].RootElement.GetProperty("tipo").GetString() == "progreso"
            && events[0].RootElement.GetProperty("etapa").GetString() == "lectura"
            && events[1].RootElement.GetProperty("tipo").GetString() == "error",
            "Streaming endpoint sends progress followed by an error for an invalid workbook");
        foreach (var evt in events) evt.Dispose();
        if (path != null)
        {
            using var file = File.OpenRead(path);
            var actual = ProductoService.ReadProductWorkbook(file);
            Console.WriteLine($"Workbook rows: {actual.Filas.Count}");
            foreach (var row in actual.Filas.Where(r => r.Errores.Count > 0)) Console.WriteLine($"Row {row.Fila}: {string.Join("; ", row.Errores)}");
            file.Position = 0;
            Check(ProductoService.ReadProductWorkbook(file).Filas.Count == 185, "Workbook stream can be reread for confirmation validation");
            Check(actual.PuedeImportar && actual.Filas.Count == 185, "Real export: all 185 rows valid");
            Check(actual.Filas.Count(r => !int.TryParse(r.Codigo, out _)) == 33, "Real export: 33 alphanumeric codes retained");
            Check(actual.Filas.Count(r => r.Precio == 0) == 42, "Real export: 42 zero-price warnings");
        }
    }
}
