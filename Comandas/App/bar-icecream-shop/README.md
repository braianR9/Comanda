# Bar and Ice Cream Shop Application

This project is a Flutter application that connects to a .NET API for managing a bar and ice cream shop. The application features a user-friendly login interface, configuration for tables in sectors, and integration with a command printer.

## Project Structure

- **flutter_app**: Contains the Flutter application code.
  - **lib**: Main directory for Dart code.
    - **main.dart**: Entry point of the Flutter application.
    - **app.dart**: Main application widget.
    - **config**: Configuration files for API connections.
    - **models**: Data models used in the application.
    - **screens**: UI screens for the application.
    - **services**: Classes for handling API calls.
    - **widgets**: Reusable UI components.
    - **utils**: Utility functions and constants.
  - **pubspec.yaml**: Flutter project configuration file.
  - **README.md**: Documentation for the Flutter application.

- **dotnet_api**: Contains the .NET API code.
  - **src**: Main source directory for the API.
    - **Controllers**: API controllers for handling requests.
    - **Models**: Data models for the API.
    - **Services**: Business logic and service classes.
    - **Data**: Database context for Entity Framework.
    - **Program.cs**: Entry point of the .NET API application.
    - **appsettings.json**: Configuration settings for the API.
  - **BarIceCreamShop.Api.csproj**: Project file for the .NET API.
  - **README.md**: Documentation for the .NET API.

## Features

- User authentication with a login interface.
- Management of tables and sectors.
- Display of current orders.
- Integration with a command printer for order printing.

## Getting Started

1. Clone the repository.
2. Navigate to the `flutter_app` directory and run `flutter pub get` to install dependencies.
3. Set up the .NET API by navigating to the `dotnet_api` directory and running the necessary commands to build and run the API.
4. Configure the API URL in `flutter_app/lib/config/api_config.dart`.
5. Run the Flutter application using `flutter run`.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.