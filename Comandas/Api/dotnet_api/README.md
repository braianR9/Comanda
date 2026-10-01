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
## Gestión de listas de precios

La pantalla **Listas de precios** incluye:

- **Planilla de precios**: compara las listas activas en columnas, filtra por rubro o búsqueda y guarda hasta 2000 celdas en una operación. Los cambios pendientes se conservan al cambiar de página. Una celda vacía elimina el precio de esa lista; cero conserva un precio de $0.
- **Modificación masiva**, dentro de una lista: aumentos o descuentos con redondeo hacia arriba, abajo o al múltiplo más cercano. La confirmación guarda los precios de la vista previa; si cambiaron entretanto, devuelve un conflicto para revisarlos.
- **Historial de cambios**: usuario, fecha, lista, producto y precio anterior/nuevo. Permite revertir un grupo completo si esos precios no tienen movimientos posteriores y las listas siguen activas. Las reversiones también quedan registradas.

### Migración

Ejecutar `database/add_price_history.sql` en la base de la aplicación, con una cuenta administradora o propietaria de las tablas. El script es transaccional y puede repetirse. Incluye permisos para el rol local `foco_api`; adaptar ese nombre en otros entornos. No modifica precios existentes. El historial registra movimientos desde su instalación, sin reconstruir cambios anteriores.

Aplicar la migración antes de iniciar esta versión de la API. Las operaciones de precios no actualizan los importes de ventas ya registradas. Las escrituras realizadas fuera de la app se identifican como `Sistema / edición de producto`.

### Verificación

Desde `App/bar-icecream-shop/flutter_app`:

```sh
flutter test test/price_grid_test.dart test/api_response_test.dart
dotnet run --project test/api_payments/ApiPaymentsRegression.csproj -- --test-price-lists
```

La prueba de integración sólo admite PostgreSQL local, necesita un producto activo existente y revierte todos sus cambios al terminar. Para probar únicamente los cálculos, usar `--test-price-calculations`.

## Promociones y aumentos programados

Aplicar también `database/add_scheduled_price_rules.sql` como administrador antes de iniciar la API. En la app: **Listas de precios → Promociones y aumentos programados**.

Cada regla pertenece a una lista y puede afectar toda la lista, un producto, un rubro o un subrubro. Admite precio fijo, aumento/descuento por porcentaje o importe y redondeo. Configuración del calendario:

- Fecha desde obligatoria y fecha hasta opcional, ambas inclusivas. Sin fecha hasta permite aumentos permanentes desde una fecha futura.
- Días de semana y horario opcional; sin horario cubre todo el día. Se usa hora argentina, UTC−3, independientemente de la zona horaria del servidor o navegador.
- Inicio incluido y fin excluido. Los horarios que cruzan medianoche pertenecen al día en que empiezan. Una regla para viernes, de 22:00 a 02:00, sigue activa el sábado hasta antes de las 02:00, incluso en su última fecha de inicio.
- Se aplica **una sola regla**: mayor prioridad, luego mayor especificidad (producto, subrubro, rubro, toda la lista) y finalmente menor ID (la más antigua). No se acumulan ajustes de reglas.

La consulta utiliza la lista explícita de la venta; si no se indica, toma la predeterminada de la sucursal y luego la de la empresa. Una lista inactiva no se puede usar explícitamente. Si ninguna regla coincide, devuelve el precio base. Las reglas no habilitan productos sin precio base ni modifican los precios guardados en la planilla.

**Consultar precio por fecha** permite simular el precio base, el final y la regla elegida. El catálogo de ventas consulta precios vigentes y los vuelve a consultar al agregar un producto; la API confirma el precio al guardar el pedido. Los renglones ya guardados conservan su importe al cambiar cantidades o al finalizar una promoción. El cambio explícito de lista con recálculo de renglones usa las reglas vigentes en ese momento.

Endpoints autenticados:

- `GET /api/listas-precios/{id}/reglas`
- `POST /api/listas-precios/{id}/reglas`
- `PUT /api/listas-precios/{id}/reglas/{ruleId}` (incluye `version` para evitar sobrescribir otra edición)
- `POST /api/listas-precios/consulta-precios`: `idListaPrecio` opcional, `productoIds` (1–100), `fecha` opcional con offset/UTC para simulación. Las ventas siempre usan el reloj del servidor.

`diasSemana` usa bits: lunes=1, martes=2, miércoles=4, jueves=8, viernes=16, sábado=32, domingo=64; todos=127. `minutoDesde` y `minutoHasta` son minutos desde medianoche (0–1439) o ambos `null`.

Verificación adicional desde la carpeta Flutter:

```sh
flutter test test/price_rules_test.dart test/sales_payments_test.dart
dotnet run --project test/api_payments/ApiPaymentsRegression.csproj -- --test-scheduled-prices
```

La integración usa una transacción local y revierte todos sus cambios.
