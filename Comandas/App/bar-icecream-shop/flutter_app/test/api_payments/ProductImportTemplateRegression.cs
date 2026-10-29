using BarIceCreamShop.Api.Services;
using ClosedXML.Excel;

// Generador reproducible del archivo que Flutter distribuye como asset.
static class ProductImportTemplateRegression
{
    static readonly string[] Headers = ["Código", "Nombre", "Costo", "Precio", "Rubro", "Subrubro", "Alicuota", "Activo"];
    public static void Generate(string path)
    {
        using var book = new XLWorkbook();
        book.Properties.Title = "focobr · Plantilla para importar productos";
        book.Properties.Author = "focobr";
        var products = book.AddWorksheet("Productos");
        var examples = book.AddWorksheet("Ejemplos");
        var instructions = book.AddWorksheet("Instrucciones");
        foreach (var sheet in new[] { products, examples })
        {
            for (var i = 0; i < Headers.Length; i++) sheet.Cell(1, i + 1).Value = Headers[i];
            sheet.Range("A1:H1").Style.Fill.BackgroundColor = XLColor.FromHtml("#6C5CE7");
            sheet.Range("A1:H1").Style.Font.FontColor = XLColor.White;
            sheet.Range("A1:H1").Style.Font.Bold = true;
            sheet.Row(1).Height = 28;
            sheet.SheetView.FreezeRows(1);
            sheet.Column(1).Width = 20; sheet.Column(2).Width = 36;
            sheet.Columns(3, 4).Width = 16; sheet.Columns(5, 6).Width = 24;
            sheet.Columns(7, 8).Width = 14;
            sheet.Column(1).Style.NumberFormat.Format = "@";
            sheet.Columns(3, 4).Style.NumberFormat.Format = "0.00";
            sheet.Column(7).Style.NumberFormat.Format = "0.##";
            sheet.Column(8).Style.NumberFormat.Format = "0";
        }
        var tips = new[] {
            "Obligatorio. Código único de referencia (hasta 100 caracteres). Se conservan letras y ceros iniciales.",
            "Obligatorio. Nombre único del producto (hasta 200 caracteres).",
            "Obligatorio. Costo con IVA incluido. Número mayor o igual a 0, sin símbolo de moneda.",
            "Obligatorio. Precio de venta con IVA incluido. Número mayor o igual a 0, sin símbolo de moneda.",
            "Obligatorio. Rubro (hasta 150 caracteres). Si no existe se crea.",
            "Opcional. Subrubro (hasta 150 caracteres). Si no existe se crea dentro del rubro.",
            "Obligatorio. Porcentaje de IVA como número: por ejemplo 21, no 21% ni 0,21. Debe existir una alícuota activa en el sistema.",
            "Obligatorio. 1 = activo, 0 = inactivo. También se aceptan sí/no o true/false al importar."
        };
        for (var i = 0; i < tips.Length; i++) products.Cell(1, i + 1).CreateComment().AddText(tips[i]);
        var active = products.Range("H2:H2001").CreateDataValidation();
        active.List("\"1,0\"", inCellDropdown: true);
        active.IgnoreBlanks = false; active.ShowInputMessage = true;
        active.InputTitle = "Estado del producto"; active.InputMessage = "1 = activo; 0 = inactivo.";
        active.ShowErrorMessage = true; active.ErrorTitle = "Estado inválido"; active.ErrorMessage = "Elegí 1 o 0.";
        var first = new object[] { "0001", "Café con leche", 800m, 1500m, "Cafetería", "Calientes", 21m, 1 };
        var second = new object[] { "P002", "Agua sin gas", 500m, 1000m, "Bebidas", "", 21m, 0 };
        for (var i = 0; i < Headers.Length; i++)
        {
            examples.Cell(2, i + 1).Value = XLCellValue.FromObject(first[i]);
            examples.Cell(3, i + 1).Value = XLCellValue.FromObject(second[i]);
        }
        string[] guide = [
            "Plantilla de importación de productos · focobr",
            "1. Completá la hoja Productos desde la fila 2. Esa es la única hoja que se importa.",
            "2. Consultá la hoja Ejemplos como referencia. Sus productos no se cargan automáticamente.",
            "3. Conservá los ocho encabezados y el nombre de la hoja Productos.",
            "4. Máximo 2000 productos y 5 MB por archivo. Para cargas mayores, dividí los productos en varios archivos.",
            "5. Guardá el archivo como .xlsx, seleccionalo en Importar Excel, revisá la vista previa y confirmá.",
            "Columnas y valores admitidos",
            .. Headers.Select((header, i) => header + ": " + tips[i]),
            "Los códigos y nombres deben ser únicos dentro del archivo. Los existentes en focobr por código importado o nombre se omiten sin modificarlos.",
            "La columna Código es una referencia externa. Focobr asigna nuevos códigos internos.",
            "Costo y Precio incluyen IVA. Escribí números sin símbolos de moneda ni separadores de miles. Se aceptan decimales con coma.",
            "La alícuota debe estar configurada y activa en focobr antes de importar. No se crean alícuotas desde este archivo.",
            "Se crean rubros y subrubros faltantes. Stock, imágenes y componentes quedan sin configurar; la visibilidad en salón, delivery y carta queda desactivada.",
            "Podés copiar y pegar muchas filas en Productos. No agregues títulos, totales ni instrucciones debajo de los productos."
        ];
        for (var i = 0; i < guide.Length; i++) instructions.Cell(i + 1, 1).Value = guide[i];
        instructions.Column(1).Width = 115;
        instructions.Column(1).Style.Alignment.WrapText = true;
        instructions.Rows(1, guide.Length).Height = 42;
        instructions.Cell(1, 1).Style.Font.Bold = true;
        instructions.Cell(1, 1).Style.Font.FontSize = 16;
        products.SetTabActive();
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        book.SaveAs(path);
        Console.WriteLine("Plantilla generada: " + path);
    }

    public static void Run(string path)
    {
        using var book = new XLWorkbook(path);
        var products = book.Worksheet("Productos");
        Check(products.RowsUsed().Count() == 1, "Downloaded template has headers and no product rows");
        using var empty = new MemoryStream(); book.SaveAs(empty); empty.Position = 0;
        try { ProductoService.ReadProductWorkbook(empty); throw new Exception("Blank template accepted as product data."); }
        catch (ProductoException) { Check(true, "Examples on other sheets are never imported automatically"); }
        var examples = book.Worksheet("Ejemplos");
        for (var row = 2; row <= 3; row++)
            for (var column = 1; column <= 8; column++) products.Cell(row, column).Value = examples.Cell(row, column).Value;
        using var saved = new MemoryStream();
        ProductImportResult Parse() { book.SaveAs(saved); using var stream = new MemoryStream(saved.ToArray()); return ProductoService.ReadProductWorkbook(stream); }
        var parsed = Parse();
        Check(parsed.PuedeImportar && parsed.Filas.Count == 2 && parsed.Filas[0].Codigo == "0001" && parsed.Filas[1].Codigo == "P002",
            "Example rows match the real importer and preserve leading zeros and alphanumeric codes");
        Check(parsed.Filas[0].Activo && !parsed.Filas[1].Activo && parsed.Filas[1].Subrubro == "", "Both product states and an optional empty subgroup are supported");
        for (var row = 4; row <= 2001; row++)
        {
            products.Cell(row, 1).Value = "P" + row; products.Cell(row, 2).Value = "Producto " + row;
            products.Cell(row, 3).Value = 100; products.Cell(row, 4).Value = 200;
            products.Cell(row, 5).Value = "Prueba"; products.Cell(row, 7).Value = 21; products.Cell(row, 8).Value = 1;
        }
        parsed = Parse();
        Check(parsed.PuedeImportar && parsed.Filas.Count == 2000, "The completed template processes 2000 products");
        products.Cell(2002, 1).Value = "EXTRA";
        try { Parse(); throw new Exception("More than 2000 products accepted."); }
        catch (ProductoException) { Check(true, "Files exceeding 2000 products are rejected"); }
    }
    static void Check(bool ok, string label) { if (!ok) throw new Exception(label); Console.WriteLine("PASS: " + label); }
}
