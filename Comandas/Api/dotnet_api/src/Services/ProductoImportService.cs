using System.Globalization;
using BarIceCreamShop.Api.Models;
using ClosedXML.Excel;
using Microsoft.EntityFrameworkCore;

namespace BarIceCreamShop.Api.Services;

public sealed class ProductImportRow
{
    public int Fila { get; set; }
    public string Codigo { get; set; } = "";
    public string Nombre { get; set; } = "";
    public string Rubro { get; set; } = "";
    public string Subrubro { get; set; } = "";
    public decimal Costo { get; set; }
    public decimal Precio { get; set; }
    public decimal Alicuota { get; set; }
    public bool Activo { get; set; }
    public bool Omitir { get; set; }
    public List<string> Errores { get; set; } = [];
    public List<string> Advertencias { get; set; } = [];
}

public sealed record ProductImportProgress(string Etapa, int Procesados = 0, int Total = 0);

public sealed class ProductImportResult
{
    public List<ProductImportRow> Filas { get; set; } = [];
    public int Importados { get; set; }
    public int Omitidos => Filas.Count(r => r.Omitir);
    public bool PuedeImportar => Filas.Count > 0 && Filas.All(r => r.Errores.Count == 0);
}

public partial class ProductoService
{
    // Pure workbook parsing; the export has a title and date before its headers.
    public static ProductImportResult ReadProductWorkbook(Stream stream)
    {
        using var workbook = new XLWorkbook(stream);
        static XLCellValue Value(IXLCell cell) => cell.HasFormula ? cell.CachedValue : cell.Value;
        static string CellText(IXLCell cell) => Value(cell).ToString(CultureInfo.InvariantCulture).Trim();
        var sheet = workbook.Worksheets.FirstOrDefault(s => s.Name.Equals("Productos", StringComparison.OrdinalIgnoreCase))
            ?? workbook.Worksheets.First();
        var header = sheet.RowsUsed().Take(20).FirstOrDefault(r =>
            r.CellsUsed().Any(c => CellText(c) == "Nombre") &&
            r.CellsUsed().Any(c => CellText(c) == "Código"))
            ?? throw new ProductoException("No se encontraron las columnas Código y Nombre en las primeras 20 filas.");
        var columns = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (var cell in header.CellsUsed())
            if (!columns.TryAdd(CellText(cell), cell.Address.ColumnNumber))
                throw new ProductoException("Hay encabezados de columna repetidos.");
        foreach (var required in new[] { "Código", "Nombre", "Costo", "Precio", "Rubro", "Subrubro", "Alicuota", "Activo" })
            if (!columns.ContainsKey(required)) throw new ProductoException($"Falta la columna {required}.");
        var totalRows = sheet.Tables.Where(t => t.ShowTotalsRow)
            .Select(t => t.RangeAddress.LastAddress.RowNumber).ToHashSet();
        var result = new ProductImportResult();
        var codes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in sheet.RowsUsed().Where(r => r.RowNumber() > header.RowNumber() && !totalRows.Contains(r.RowNumber())))
        {
            string Text(string key) => CellText(row.Cell(columns[key]));
            if (columns.Values.All(c => row.Cell(c).IsEmpty())) continue;
            if (result.Filas.Count >= 2000) throw new ProductoException("El archivo admite hasta 2000 productos.");
            var item = new ProductImportRow { Fila = row.RowNumber(), Codigo = Text("Código"), Nombre = Text("Nombre"),
                Rubro = Text("Rubro"), Subrubro = Text("Subrubro") };
            decimal Number(string key, decimal max)
            {
                var cell = row.Cell(columns[key]);
                decimal value;
                var numeric = Value(cell);
                var valid = numeric.IsNumber
                    ? decimal.TryParse(numeric.GetNumber().ToString(CultureInfo.InvariantCulture), NumberStyles.Float, CultureInfo.InvariantCulture, out value)
                    : decimal.TryParse(Text(key), NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign, CultureInfo.GetCultureInfo("es-AR"), out value);
                if (!valid || value < 0 || value > max) item.Errores.Add($"{key}: número inválido o fuera de rango.");
                return value;
            }
            item.Costo = Number("Costo", 9999999999999999.99m);
            item.Precio = Number("Precio", 9999999999999999.99m);
            item.Alicuota = Number("Alicuota", 100);
            var active = Text("Activo").ToLowerInvariant();
            item.Activo = active is "1" or "true" or "sí" or "si";
            if (active is not ("1" or "0" or "true" or "false" or "sí" or "si" or "no")) item.Errores.Add("Activo debe ser 1/0, sí/no o true/false.");
            if (item.Codigo.Length is 0 or > 100) item.Errores.Add("Código obligatorio, de hasta 100 caracteres.");
            if (item.Nombre.Length is 0 or > 200) item.Errores.Add("Nombre obligatorio, de hasta 200 caracteres.");
            if (item.Rubro.Length is 0 or > 150 || item.Subrubro.Length > 150) item.Errores.Add("Rubro obligatorio; rubro y subrubro admiten hasta 150 caracteres.");
            if (!codes.Add(item.Codigo)) item.Errores.Add("Código repetido en el archivo.");
            if (!names.Add(item.Nombre)) item.Errores.Add("Nombre repetido en el archivo.");
            if (item.Precio == 0) item.Advertencias.Add("Precio cero.");
            if (item.Rubro.Equals("Combo", StringComparison.OrdinalIgnoreCase)) item.Advertencias.Add("Se creará como producto simple; configurar componentes después.");
            result.Filas.Add(item);
        }
        if (result.Filas.Count == 0) throw new ProductoException("El archivo no contiene productos.");
        return result;
    }

    public async Task<ProductImportResult> ImportWorkbookAsync(int company, int branch, Stream stream, bool confirm,
        Func<ProductImportProgress, Task>? progress = null)
    {
        async Task Report(string stage, int processed = 0, int total = 0)
        {
            if (progress != null) await progress(new(stage, processed, total));
        }
        await Report("lectura");
        var result = ReadProductWorkbook(stream);
        await Report("referencias", 0, result.Filas.Count);
        await ValidateBranchAsync(company, branch);
        await using var transaction = confirm ? await _context.Database.BeginTransactionAsync() : null;
        // Serialize imports for this company, including the duplicate check.
        if (confirm) await _context.Database.ExecuteSqlInterpolatedAsync($"SELECT pg_advisory_xact_lock(73421, {company})");
        var products = await _context.Productos.AsNoTracking().Where(p => p.IdEmpresa == company)
            .Select(p => new { p.Nombre, p.CodigoImportacion }).ToListAsync();
        var existingCodes = products.Where(p => p.CodigoImportacion != null).Select(p => p.CodigoImportacion!).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var existingNames = products.Select(p => p.Nombre.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var taxes = await _context.Alicuotas.Where(a => a.Activa && (a.IdEmpresa == company || a.IdEmpresa == null)).ToListAsync();
        var groups = await _context.Rubros.Where(r => r.IdEmpresa == company).ToListAsync();
        var subgroups = await _context.SubRubros.Where(r => r.IdEmpresa == company).ToListAsync();
        var validated = 0;
        await Report("validacion", 0, result.Filas.Count);
        foreach (var row in result.Filas)
        {
            row.Omitir = existingCodes.Contains(row.Codigo) || existingNames.Contains(row.Nombre);
            if (row.Omitir) row.Advertencias.Add("Ya existe por código importado o nombre; se omitirá sin modificarlo.");
            if (!taxes.Any(t => t.Porcentaje == row.Alicuota)) row.Errores.Add($"No existe una alícuota activa de {row.Alicuota}%.");
            var group = groups.FirstOrDefault(g => g.Nombre.Equals(row.Rubro, StringComparison.OrdinalIgnoreCase));
            if (group is { Activo: false }) row.Errores.Add("El rubro existente está inactivo.");
            if (group != null && subgroups.Any(s => s.IdRubro == group.Id && s.Nombre.Equals(row.Subrubro, StringComparison.OrdinalIgnoreCase) && !s.Activo))
                row.Errores.Add("El subrubro existente está inactivo.");
            validated++;
            if (validated % 20 == 0 || validated == result.Filas.Count)
                await Report("validacion", validated, result.Filas.Count);
        }
        if (!confirm || !result.PuedeImportar) return result;
        var newRows = result.Filas.Where(r => !r.Omitir).ToList();
        await Report("guardado", 0, newRows.Count);
        foreach (var row in newRows)
        {
            var group = groups.FirstOrDefault(g => g.Nombre.Equals(row.Rubro, StringComparison.OrdinalIgnoreCase));
            if (group == null)
            {
                group = new Rubro { IdEmpresa = company, Nombre = row.Rubro };
                _context.Rubros.Add(group);
                await _context.SaveChangesAsync();
                groups.Add(group);
            }
            SubRubro? subgroup = null;
            if (row.Subrubro.Length > 0)
            {
                subgroup = subgroups.FirstOrDefault(s => s.IdRubro == group.Id && s.Nombre.Equals(row.Subrubro, StringComparison.OrdinalIgnoreCase));
                if (subgroup == null)
                {
                    subgroup = new SubRubro { IdEmpresa = company, IdRubro = group.Id, Nombre = row.Subrubro };
                    _context.SubRubros.Add(subgroup);
                    await _context.SaveChangesAsync();
                    subgroups.Add(subgroup);
                }
            }
            var saved = await CreateAsync(company, branch, new CreateProductRequest {
                Nombre = row.Nombre, IdRubro = group.Id, IdSubRubro = subgroup?.Id,
                IdAlicuota = taxes.OrderByDescending(t => t.IdEmpresa == company).First(t => t.Porcentaje == row.Alicuota).Id,
                CostoConIva = row.Costo, PrecioConIva = row.Precio
            });
            var entity = await GetEntityAsync(company, saved.Id);
            entity.CodigoImportacion = row.Codigo;
            entity.Activo = row.Activo;
            await _context.SaveChangesAsync();
            result.Importados++;
            await Report("guardado", result.Importados, newRows.Count);
        }
        await Report("confirmacion", result.Importados, newRows.Count);
        await transaction!.CommitAsync();
        return result;
    }
}
