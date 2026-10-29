# focobr

This Flutter application serves as the front-end for a bar and ice cream shop, connecting to a .NET API for backend services. The app features a user-friendly login interface, configuration for tables in sectors, and integration with a command printer.

## Features

En **Productos → Importar Excel → Descargar plantilla Excel** se descarga
`assets/templates/plantilla_productos_focobr.xlsx`, incluido en la app sin consultar
a la API. Completá la hoja **Productos**; **Ejemplos** e **Instrucciones** son de
referencia y no se importan. Admite hasta 2000 productos y 5 MB por archivo.
Las columnas son Código, Nombre, Costo, Precio, Rubro, Subrubro, Alicuota y Activo.
Costo y Precio incluyen IVA; Alicuota es el porcentaje numérico (por ejemplo 21).

Para regenerar y comprobar la plantilla desde esta carpeta:
`dotnet run --project test/api_payments -- --write-product-template`.
Para comprobar el asset existente sin modificarlo:
`dotnet run --project test/api_payments -- --test-product-template`.
Estas comprobaciones usan el lector real de la API y no acceden a la base de datos.
Prueba de descarga y diseño adaptable: `flutter test test/product_import_template_test.dart`.

- **User Authentication**: Secure login interface for users.
- **Table Management**: View and manage tables organized by sectors.
- **Order Management**: Create and view orders associated with tables.
- **Printer Integration**: Send commands to printers for order processing.

## Project Structure

```
bar-icecream-shop
├── flutter_app
│   ├── lib
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── config
│   │   │   └── api_config.dart
│   │   ├── models
│   │   │   ├── user.dart
│   │   │   ├── table.dart
│   │   │   ├── sector.dart
│   │   │   ├── order.dart
│   │   │   └── printer.dart
│   │   ├── screens
│   │   │   ├── login
│   │   │   │   └── login_screen.dart
│   │   │   ├── home
│   │   │   │   └── home_screen.dart
│   │   │   ├── sectors
│   │   │   │   └── sectors_screen.dart
│   │   │   ├── tables
│   │   │   │   └── tables_screen.dart
│   │   │   └── orders
│   │   │       └── orders_screen.dart
│   │   ├── services
│   │   │   ├── auth_service.dart
│   │   │   ├── table_service.dart
│   │   │   ├── order_service.dart
│   │   │   └── printer_service.dart
│   │   ├── widgets
│   │   │   ├── table_card.dart
│   │   │   └── sector_grid.dart
│   │   └── utils
│   │       └── constants.dart
│   ├── pubspec.yaml
│   └── README.md
├── dotnet_api
│   ├── src
│   │   ├── Controllers
│   │   │   ├── AuthController.cs
│   │   │   ├── TablesController.cs
│   │   │   ├── SectorsController.cs
│   │   │   ├── OrdersController.cs
│   │   │   └── PrinterController.cs
│   │   ├── Models
│   │   │   ├── User.cs
│   │   │   ├── Table.cs
│   │   │   ├── Sector.cs
│   │   │   ├── Order.cs
│   │   │   └── PrintJob.cs
│   │   ├── Services
│   │   │   ├── AuthService.cs
│   │   │   ├── TableService.cs
│   │   │   ├── OrderService.cs
│   │   │   └── PrinterService.cs
│   │   ├── Data
│   │   │   └── AppDbContext.cs
│   │   ├── Program.cs
│   │   └── appsettings.json
│   ├── BarIceCreamShop.Api.csproj
│   └── README.md
└── README.md
```

## Getting Started

1. Clone the repository.
2. Navigate to the `flutter_app` directory.
3. Run `flutter pub get` to install dependencies.
4. Configure the API settings in `lib/config/api_config.dart`.
5. Run the application using `flutter run`.

## API Integration

The application communicates with a .NET API for data management. Ensure the API is running and accessible before using the app.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any enhancements or bug fixes.
