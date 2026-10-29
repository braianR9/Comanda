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

### Configuración local (secretos)

Los secretos no se versionan. Cada instalación necesita sus propios valores:

1. Copiar `src/appsettings.Local.example.json` a `src/appsettings.Local.json` y completar la cadena de conexión, `ApiKey:Value`, `Jwt:Key` (mínimo 32 caracteres) y la ruta de credenciales de Google Sheets. También se pueden usar variables de entorno (`ConnectionStrings__DefaultConnection`, `ApiKey__Value`, `Jwt__Key`).
2. En la app Flutter, copiar `config/local.example.json` a `config/local.json` con la misma API Key, y ejecutar con `flutter run --dart-define-from-file=config/local.json` (VS Code ya lo pasa en `.vscode/launch.json`).

La API no arranca si falta alguno de estos valores.

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

## Venta directa (punto de venta sin mesa) y código de barras

Para negocios sin mesas (kiosco, mostrador, venta rápida), **Venta directa** reutiliza todo el circuito de ventas existente (comandas, descuentos, pagos, caja, impresión) contra una mesa virtual "Mostrador", en vez de requerir una mesa física.

- La mesa y el sector "Mostrador" se crean solos, por empresa/sucursal, la primera vez que se usan (`GET /api/pos/mostrador`). No requieren backfill manual.
- El sector "Mostrador" es de sistema: no aparece en la grilla de sectores ni se puede editar desde la pantalla de Sectores.
- A diferencia de una mesa física, "Mostrador" admite **varias ventas simultáneas** (varios cajeros/puestos a la vez); su estado Libre/Ocupada no se usa.
- Cerrar una venta de mostrador no bloquea nada: la siguiente venta arranca vacía de inmediato en la app.

**Código de barras**: los productos tienen un campo opcional `codigoBarras`, único por empresa. `GET /api/productos/codigo-barras/{codigo}` resuelve el producto activo exacto para el pistoleo en el punto de venta; un lector USB/Bluetooth típico actúa como teclado (no requiere integración especial).

### Migración

Ejecutar `database/add_pos_mostrador.sql` con una cuenta administradora o propietaria de las tablas (igual que el resto de migraciones). Agrega `es_sistema` a `sectores`, `es_mostrador` a `mesas` y `codigo_barras` a `productos`, todas columnas nuevas y opcionales; no modifica datos existentes.

Endpoints nuevos:

- `GET /api/pos/mostrador`: `{ tableId, tableName }` de la mesa de venta directa de la sucursal actual (la crea si no existe).
- `GET /api/productos/codigo-barras/{codigo}`: producto activo con ese código exacto, o 404.


## Composición de productos y cobros combinados

En Productos, al elegir **Producto compuesto**, la sección **Composición del producto** permite buscar productos simples activos por nombre o código, agregar cantidades por unidad y quitar componentes. La búsqueda consulta el catálogo de la empresa, independientemente de la página visible en Productos. Admite hasta tres decimales; los componentes con stock configurado como entero deben consumirse en cantidades enteras.

El producto y su composición se guardan en una misma transacción. Un compuesto requiere al menos un componente simple activo de la misma empresa; no admite duplicados ni otros compuestos. Cambiarlo a simple elimina su composición. No se puede convertir a compuesto un producto que forme parte de otra composición.

Al finalizar el cobro, cada cantidad de componente se multiplica por las unidades vendidas y se descuenta de su stock en la sucursal. No se descuenta el stock del producto compuesto. Reintentar un cierre no duplica estos movimientos. Usa la tabla `producto_componentes` del módulo de stock existente, sin migración adicional.

En el diálogo de cobro, **Agregar otro medio de pago** completa el saldo aún no asignado. Se muestra el saldo después de los medios anteriores y el faltante/excedente total. Si se cambia un importe anterior, **Completar saldo con este medio** ajusta el siguiente importe. Los recargos y descuentos se aplican a la porción de cuenta asignada a cada medio.

Pruebas desde la carpeta Flutter:

```sh
flutter test test/sales_payments_test.dart test/product_components_test.dart test/api_response_test.dart
dotnet run --project test/api_payments/ApiPaymentsRegression.csproj -- --test-product-components
```

La integración exige PostgreSQL local y revierte todos los datos de prueba al terminar.

### Empresa y compras

Aplicar `database/add_company_purchases.sql` como propietario de las tablas (requiere el módulo de movimientos de stock). El script es repetible y conserva los datos existentes. Luego reiniciar la API y recargar Flutter.

- **Configuración → Empresa y facturación**: nombre comercial, imagen y contacto; segunda pestaña para datos fiscales y parámetros previstos de ARCA. Son datos preparatorios: no se emiten comprobantes ni se almacenan claves privadas.
- **Compras → Proveedores**: datos esenciales y productos simples asociados, con código del proveedor opcional. ADMIN y ENCARGADO administran proveedores; EMPLEADO puede consultarlos.
- **Compras → Comprobantes de compra**: factura o remito, proveedor, fecha, número, cantidades y costos. Los borradores se pueden editar y todavía no afectan stock. La sucursal proviene de la sesión.
- **Controlar e ingresar al stock**: sólo ADMIN/ENCARGADO. Verifica la versión, registra cantidades y movimientos y cambia a Controlado en una transacción. Las cantidades respetan Entero/Decimal del producto. Debe existir configuración de stock en esa sucursal. No modifica precios de venta.
- Una compra controlada queda sin edición. Sólo los borradores pueden anularse, con motivo. Las devoluciones de compras no forman parte de este circuito.
- Cada creación, edición, control y anulación guarda usuario, fecha, motivo y copia completa del comprobante. El rol `foco_api` no recibe permisos para reescribir o eliminar ese historial.
- La clave de solicitud evita repetir una carga tras perder una respuesta. El comprobante es único por empresa/proveedor/tipo/letra/punto de venta/número normalizado (excepto anulados). El control repetido no duplica movimientos ni stock.

Pruebas de interfaz: `flutter test test/purchases_test.dart` en la app. Para pruebas transaccionales, usar una **base temporal vacía** en `127.0.0.1:55439`: restaurar sólo el esquema de la aplicación, ejecutar la migración, `test/api_payments/PurchasesSeed.sql` y nuevamente la migración para comprobar permisos. Ejecutar `dotnet run --project test/api_payments -- --test-purchases` con `COMPRAS_TEST_CONNECTION` apuntando a esa base como `foco_api`. El test rechaza otros hosts/puertos y verifica concurrencia, rollback, aislamiento, roles e historial; no usar datos reales.

## Facturación electrónica AFIP/ARCA

Integración directa con WSAA (autenticación) y WSFEv1 (factura electrónica). Monotributo y exentos emiten C; responsables inscriptos emiten A (a inscriptos y monotributistas) y B al resto, con IVA discriminado por alícuota. El total facturado incluye descuentos y recargos de pago, repartidos entre las alícuotas.

### Migración

Ejecutar, en orden, `database/add_facturacion_afip.sql`, `database/add_nota_credito_motivo.sql` y `database/add_reimpresion_comprobantes.sql` como propietario de las tablas (`postgres`) **antes** de iniciar esta versión de la API: agrega `ventas.id_cliente`, que la API ya lee.

### Configuración

- `Afip:CredentialKey` en `appsettings.Local.json`: 32 bytes en base64 (`openssl rand -base64 32`). Cifra la clave privada del certificado; si se pierde, hay que generar otro certificado.
- En *Configuración › Empresa y facturación*: razón social, CUIT, condición IVA, punto de venta, ambiente (`Homologacion` o `Produccion`) y modo (`Manual` o `Automatico` al cobrar).
- Certificado: la API genera la clave y el pedido (CSR, `POST /api/afip/certificado/csr`); el certificado que entrega AFIP se carga con `PUT /api/afip/certificado` y se verifica con `POST /api/afip/probar`.

### Endpoints

- `POST /api/sales/{id}/facturar` (opcional: `customerId`, o `documentType` + `documentNumber`)
- `GET /api/sales/{id}/comprobantes`
- `POST /api/comprobantes/{id}/nota-credito` con `{ "reason": "..." }` obligatorio (ADMIN o ENCARGADO)
- `POST /api/comprobantes/{id}/reimprimir`: vuelve a imprimir un comprobante autorizado (marcado "REIMPRESION"; queda registrado el usuario)
- `GET /api/comprobantes` y `GET /api/facturacion/pendientes`: historial con usuario y fecha, y ventas cobradas sin factura vigente

Si AFIP no responde, el comprobante queda `Procesando` y el siguiente intento lo verifica con `FECompConsultar` antes de numerar, para no duplicarlo.

### Pruebas

```sh
cd App/bar-icecream-shop/flutter_app/test/api_payments
dotnet run -- --test-afip          # cálculos
dotnet run -- --test-afip --live   # además, comunicación con homologación
```

### Importación de productos desde Excel

Antes de desplegar esta versión de la API, ejecutar `database/add_producto_importacion.sql`
contra la base correspondiente. Agrega una columna nullable y un índice por empresa;
no carga productos ni cambia los existentes. Desplegar luego la API y la aplicación Flutter.

En **Mis productos**, el botón **Importar Excel** permite seleccionar un `.xlsx` (máximo
5 MB y 2000 productos), revisar todas las filas y confirmar. Es compatible con el
exportado de Productos cuyo encabezado aparece después del título y fecha. Columnas:
`Código`, `Nombre`, `Costo`, `Precio`, `Rubro`, `Subrubro`, `Alicuota`, `Activo`.
Costo y Precio incluyen IVA; Alicuota es el porcentaje, no el ID. Los valores numéricos
nativos de Excel y los textos decimales con coma están admitidos.

La vista previa no escribe datos. La confirmación vuelve a validar y guarda todo en una
transacción: cualquier error revierte la carga completa. Se crean los rubros/subrubros
faltantes y se usa una alícuota activa existente de la empresa o global con ese porcentaje.
Los productos reciben código interno automático, guardan el código externo (incluidos
`S01`, etc.) en `codigo_importacion` y actualizan la lista de precios predeterminada.
Los existentes por código importado o nombre (sin distinguir mayúsculas) se omiten sin
actualizar precios ni otros campos. No se vacía el catálogo existente.

Se crean productos simples, sin stock ni componentes; los combos requieren configuración
posterior. Salón, delivery y carta digital quedan desactivados hasta configurarlos. Se
conserva el estado Activo del archivo. Precios cero generan advertencias, no errores.
Imagen, descripción, preparación y código de barras quedan vacíos.

Prueba del lector sin conexión a base de datos:

```sh
dotnet run --project ../../App/bar-icecream-shop/flutter_app/test/api_payments -- --test-product-import
# Opcional: agregar --workbook /ruta/al/exportado.xlsx para validar el archivo de 185 productos.
```

La importación muestra etapas, tiempo transcurrido y avance por productos procesados.
Durante el guardado estima el tiempo restante usando el ritmo real de procesamiento;
la confirmación de la transacción y la actualización del catálogo se muestran aparte.
Requiere actualizar tanto la API como Flutter. No hay cambios adicionales de esquema.
El cliente solicita `POST /api/productos/importar?progreso=true` y consume eventos
NDJSON (`progreso`, `resultado`, `error`). La respuesta normal JSON sigue disponible
sin ese parámetro. Los proxies deben permitir streaming (la API envía
`X-Accel-Buffering: no`); con buffering los eventos pueden aparecer todos al finalizar.
Prueba del lector de eventos: `dart run test/product_import_stream_regression.dart`
desde la carpeta Flutter.

### Comprobar stock al seleccionar productos

La casilla **Comprobar stock al vender** se aplica al agregar un producto al pedido,
al leerlo por código de barras y al aumentar su cantidad. Flutter consulta
`POST /api/sales/validate-stock` con el pedido propuesto antes de cambiar el borrador.
La API también valida al crear y modificar renglones. Se suman todas las cantidades
del mismo producto, incluidas las consumidas por distintos combos.

Esta comprobación no reserva ni descuenta inventario. El cobro registra el consumo
sin volver a rechazar el pedido por disponibilidad. Los productos sin stock configurado
y los que tienen la casilla desactivada permiten vender sin ese bloqueo. Las alarmas
son independientes de esta casilla. No requiere cambios de esquema.

Prueba transaccional local (revierte los datos de prueba):
`dotnet run --project test/api_payments -- --test-stock-sale` desde la carpeta Flutter.

### Empleado y Caja en pedidos

- **EMPLEADO** toma pedidos, modifica cantidades/comentarios y envía comandas o cambios.
  No tiene controles de cobro, descuentos, listas de precios ni facturación.
- **CAJA** y **ADMIN** pueden cobrar y ajustar el precio unitario de un renglón enviado,
  antes de registrar pagos. En la comanda aparece un lápiz junto al importe.
  El cambio recalcula subtotal, descuento y total; no cambia el catálogo ni sus listas
  y no obliga a reenviar cocina. Con pagos registrados, el precio queda bloqueado.
- El rol anterior **ENCARGADO** se muestra como **CAJA** y conserva su ID y usuarios;
  se aceptan los tokens anteriores. No requiere migrar roles ni volver a crear cuentas.
  En instalaciones nuevas, `add_roles_seed.sql` crea CAJA y evita duplicarlo si ya existe ENCARGADO.

La política `Cashier` protege en la API pagos, checkout, descuentos, precios de cuenta,
facturación y modificaciones de catálogo/listas de precios. El cliente no puede habilitar
estas acciones alterando los controles visuales. `PUT /api/sales/{id}/items/{itemId}/price`
recibe `unitPrice` y `version`; exige una cuenta enviada sin cambios de cocina ni pagos.
Actualizar API y Flutter; no hay cambios adicionales de esquema.

Pruebas: `flutter test test/sales_payments_test.dart` y
`dotnet run --project test/api_payments -- --test-cashier` desde la carpeta Flutter.
La segunda usa PostgreSQL local y revierte los datos de prueba sin emitir ni imprimir.

### Caja y cuentas pendientes

No se permite cerrar la caja de una sucursal mientras tenga ventas en `Abierta`,
`EnPedido`, `PedidoEnviado` o `ConCambios`, incluidos pedidos de mostrador y cuentas
con pagos parciales pendientes de completar. La respuesta indica las mesas/ventas
que deben cobrarse o anularse. Las cuentas de otras sucursales no bloquean el cierre.

Seleccionar/agregar productos, enviar comandas, registrar pagos y finalizar un cobro
requiere una caja abierta. El cierre y las operaciones que crean ventas o registran
pagos coordinan el acceso con un bloqueo transaccional de la fila de caja para evitar
cerrarla entre la comprobación y el guardado. Flutter vuelve a comprobar la caja antes
de mostrar el cobro, en lugar de confiar solo en el estado almacenado en pantalla.

Las cuentas anteriores no se borran, cobran ni anulan automáticamente. Si ya quedó
una cuenta abierta con caja cerrada, se puede abrir una caja para resolverla o anular
el pedido si corresponde. No requiere migración de esquema.

Pruebas desde Flutter: `dotnet run --project test/api_payments -- --test-cash-closing`
y `flutter test test/sales_payments_test.dart`. Las pruebas de base de datos crean
sus sucursales/cajas temporales dentro de una transacción que se revierte.

### Anular ventas finalizadas sin comprobante

Aplicar `database/add_sale_voids.sql` como propietario de la base antes de actualizar
API y Flutter. Agrega `venta_anulaciones`, `venta_devoluciones` y el origen de stock
`AnulacionVenta`; mantiene ventas y pagos existentes.

En **Comprobantes → Ventas sin facturar → Anular venta**, ADMIN y CAJA pueden anular
una venta finalizada con motivo obligatorio (3–500 caracteres). También hay un acceso
desde el listado de ventas. La pestaña **Ventas anuladas** conserva quién, cuándo,
motivo e importe devuelto. Los empleados no pueden ejecutar esta operación.

La anulación conserva el total original, fecha de cobro, productos y pagos; cambia la
venta a `Cancelada` e incrementa su versión. No libera ni modifica la mesa, que puede
tener otro pedido. Exige caja abierta y registra una devolución por cada pago original,
con su mismo medio de pago. Caja y transacciones descuentan las devoluciones del turno
actual. Los cierres de caja anteriores conservan sus importes guardados.

Siempre se repone el stock efectivamente descontado por la venta, usando los movimientos
originales de productos y componentes. Se conserva la composición histórica aunque el
combo haya cambiado. Las ventas sin descuento de stock no crean inventario al anular.
Una versión desactualizada, anulación repetida o comprobante autorizado/pendiente bloquea
la operación. La emisión fiscal y la anulación se coordinan mediante el mismo bloqueo
por venta. La devolución, el stock, la auditoría y el cambio de estado son transaccionales.

Los informes de ventas excluyen la venta anulada y Sistemas muestra las devoluciones
como movimientos negativos. Se cancelan sincronizaciones pendientes de esa venta; no se
reescriben archivos exportados ni filas que ya se enviaron a Google Sheets.

Pruebas desde Flutter: `flutter test test/sale_void_test.dart` y
`dotnet run --project test/api_payments -- --test-sale-void`. La segunda usa tablas
temporales de historial y revierte todos los datos de prueba de PostgreSQL local.

### Acceso exclusivo de sistemas

El enlace **Acceso de sistemas** del login abre un panel separado para el propietario
de focobr. No es un rol de `usuarios`: ningún ADMIN, CAJA o EMPLEADO puede concederlo,
ni obtiene acceso global por usar el mismo correo. La identidad se configura solamente
en el servidor mediante `SystemsOwner:Email` y `SystemsOwner:PasswordHash` (BCrypt).

Instalación, desde `Api/dotnet_api`:

1. Ejecutar `database/add_systems_admin.sql` como propietario de la base (`postgres`).
   Crea el historial, conserva los datos existentes y concede al rol local `foco_api`
   lectura, inserción y actualización de la resolución/nota. Adaptar ese rol en otros entornos.
2. Ejecutar `dotnet run -- --setup-systems --email propietario@ejemplo.com`.
   Solicita la contraseña sin mostrarla (mínimo 12 caracteres, máximo 72 bytes).
   Alternativamente, agregar `--generate-password`: genera una contraseña aleatoria y
   la guarda en `.systems-owner-credentials.txt`, privado y excluido de Git/Docker.
   Guardar la contraseña en un gestor y borrar ese archivo una vez copiada.
3. Reiniciar la API y actualizar Flutter. El correo y el hash se guardan en
   `src/appsettings.Local.json`. Conservar este archivo en almacenamiento persistente.
   Para recuperar/cambiar la cuenta desde el servidor, repetir el comando con `--reset-owner`.

En un servicio en la nube también se pueden usar los secretos `SystemsOwner__Email`
y `SystemsOwner__PasswordHash`; no usar una contraseña en texto plano en la segunda
variable. Si se usa esta modalidad, la contraseña se cambia en los secretos del servicio.
La cuenta local no se propaga automáticamente a otra API/base de datos.

El panel permite crear/editar y habilitar/deshabilitar empresas, sucursales y usuarios,
asignar sucursal y rol, y restablecer contraseñas. La identidad de sistemas puede
recuperar incluso al último administrador deshabilitado de un comercio. Cada modificación
guarda una auditoría con los datos anteriores y nuevos, sin contraseñas.

Las transacciones se filtran por empresa, sucursal, período y estado. **Ventas** usa
la fecha de cierre (apertura para cuentas pendientes) y totaliza ventas finalizadas.
**Cobros** usa la fecha real de cada pago y muestra su medio de pago. Los rangos son
`[desde, hasta)`, de hasta 366 días, con paginación y totales diarios según la zona
horaria enviada por la aplicación. Los pagos divididos no duplican los totales de venta.
El detalle de cada venta muestra productos, precios, descuentos y pagos registrados.

Los errores HTTP 500, excepciones de la API, errores de trabajadores de impresión/Sheets
y errores Flutter/Dart de sesiones autenticadas se registran desde esta instalación.
Incluyen fecha UTC, origen, empresa/sucursal/usuario cuando corresponda, referencia y
detalle técnico; se pueden filtrar y marcar como resueltos con una nota. No se guardan
cuerpos de pedidos HTTP, cabeceras, cookies ni parámetros de consulta, y se ocultan
secretos configurados, contraseñas etiquetadas y tokens. Si la base no responde o se
llena la cola de 1000 eventos, se guarda un respaldo en `logs/systems-fallback-*.jsonl`
del servidor; esos archivos se revisan allí y no se muestran en el panel.

La sesión de sistemas permanece en memoria y dura 30 minutos. Cambiar su contraseña
revoca sus sesiones anteriores. Cada solicitud autenticada de un comercio comprueba
que el usuario, su rol, empresa y sucursal sigan habilitados, y que no haya cambiado
su contraseña o sucursal. Las sesiones emitidas antes de esta versión requieren iniciar
sesión nuevamente. El login de sistemas limita intentos por IP.

Pruebas desde Flutter: `flutter test test/system_admin_test.dart` y
`dotnet run --project test/api_payments -- --test-systems`. Las pruebas usan una tabla
temporal de eventos y revierten empresas, sucursales, usuarios y transacciones creadas.
