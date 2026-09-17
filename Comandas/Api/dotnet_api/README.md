# .NET API for Bar and Ice Cream Shop

This project is a .NET API designed to support a bar and ice cream shop application. It provides endpoints for managing users, tables, sectors, orders, and printers.

## Features

- **User Authentication**: Secure login and user management.
- **Table Management**: Create, read, update, and delete tables.
- **Sector Management**: Manage different sectors within the shop.
- **Order Management**: Handle customer orders efficiently.
- **Printer Integration**: Manage print jobs for order receipts.

## Getting Started

### Prerequisites

- .NET SDK (version 6.0 or later)
- A database (e.g., SQL Server) for data storage

### Installation

1. Clone the repository:
   ```
   git clone <repository-url>
   ```
2. Navigate to the `dotnet_api` directory:
   ```
   cd dotnet_api
   ```
3. Restore the dependencies:
   ```
   dotnet restore
   ```

### Running the API

To run the API, use the following command:
```
dotnet run
```

The API will be available at `http://localhost:5000` by default.

### API Endpoints

- **Authentication**: `/api/auth/login`
- **Tables**: `/api/tables`
- **Sectors**: `/api/sectors`
- **Orders**: `/api/orders`
- **Printers**: `/api/printers`

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

## License

This project is licensed under the MIT License. See the LICENSE file for details.