using Microsoft.EntityFrameworkCore;
using BarIceCreamShop.Api.Models;

namespace BarIceCreamShop.Api.Data
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
        {
        }

        public DbSet<Usuario> Usuarios { get; set; }
        public DbSet<Empresa> Empresas { get; set; }
        public DbSet<Sucursal> Sucursales { get; set; }
        public DbSet<Rol> Roles { get; set; }
        public DbSet<Order> Orders { get; set; }
        public DbSet<Table> Tables { get; set; }
        public DbSet<Sector> Sectors { get; set; }
        public DbSet<PrintJob> PrintJobs { get; set; }
        public DbSet<PrinterConfiguration> PrinterConfigurations { get; set; }
        public DbSet<Producto> Productos { get; set; }
        public DbSet<Rubro> Rubros { get; set; }
        public DbSet<SubRubro> SubRubros { get; set; }
        public DbSet<Alicuota> Alicuotas { get; set; }
        public DbSet<ProductoCodigoContador> ProductoCodigoContadores { get; set; }
        public DbSet<StockProducto> StockProductos { get; set; }
        public DbSet<StockMovement> StockMovements { get; set; }
        public DbSet<ProductComponent> ProductComponents { get; set; }
        public DbSet<Customer> Customers { get; set; }
        public DbSet<CustomerCounter> CustomerCounters { get; set; }
        public DbSet<Discount> Discounts { get; set; }
        public DbSet<PaymentType> PaymentTypes { get; set; }
        public DbSet<Card> Cards { get; set; }
        public DbSet<SalePayment> SalePayments { get; set; }
        public DbSet<KitchenCommand> KitchenCommands { get; set; }
        public DbSet<KitchenCommandLine> KitchenCommandLines { get; set; }
        public DbSet<SaleJoinedTable> SaleJoinedTables { get; set; }
        public DbSet<SaleCounter> SaleCounters { get; set; }

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            base.OnModelCreating(modelBuilder);

            modelBuilder.Entity<Usuario>().HasKey(u => u.Id);
            modelBuilder.Entity<Empresa>().HasKey(e => e.Id);
            modelBuilder.Entity<Sucursal>().HasKey(s => s.Id);
            modelBuilder.Entity<Rol>().HasKey(r => r.Id);
            modelBuilder.Entity<Sector>().ToTable("sectores");
            modelBuilder.Entity<Sector>().HasKey(s => s.Id);
            modelBuilder.Entity<Sector>().HasIndex(s => new { s.IdEmpresa, s.Nombre }).IsUnique();
            modelBuilder.Entity<Table>().ToTable("mesas");
            modelBuilder.Entity<Table>().HasKey(t => t.Id);
            modelBuilder.Entity<Table>().HasIndex(t => new { t.IdSucursal, t.Nombre }).IsUnique();
            modelBuilder.Entity<Table>().HasOne(t => t.Sector).WithMany().HasForeignKey(t => t.SectorId).OnDelete(DeleteBehavior.Restrict);
            modelBuilder.Entity<Order>().HasKey(v => v.Id);
            modelBuilder.Entity<Order>().HasIndex(v => new { v.IdEmpresa, v.Numero }).IsUnique();
            modelBuilder.Entity<Order>().Property(v => v.Version).IsConcurrencyToken();
            modelBuilder.Entity<Order>().HasOne(v => v.Table).WithMany().HasForeignKey(v => v.TableId).OnDelete(DeleteBehavior.Restrict);
            modelBuilder.Entity<Order>().HasMany(v => v.Items).WithOne().HasForeignKey(i => i.OrderId).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<Order>().HasMany(v => v.Payments).WithOne().HasForeignKey(p => p.OrderId).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<Order>().HasMany(v => v.Commands).WithOne().HasForeignKey(c => c.OrderId).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<Order>().HasMany(v => v.JoinedTables).WithOne().HasForeignKey(j => j.OrderId).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<OrderItem>().HasKey(i => i.Id);
            modelBuilder.Entity<OrderItem>().HasIndex(i => new { i.OrderId, i.ProductId }).IsUnique();
            modelBuilder.Entity<Discount>().HasKey(d => d.Id);
            modelBuilder.Entity<PaymentType>().HasKey(p => p.Id);
            modelBuilder.Entity<Card>().HasKey(c => c.Id);
            modelBuilder.Entity<SalePayment>().HasKey(p => p.Id);
            modelBuilder.Entity<KitchenCommand>().HasKey(c => c.Id);
            modelBuilder.Entity<KitchenCommand>().HasIndex(c => new { c.IdEmpresa, c.Numero }).IsUnique();
            modelBuilder.Entity<KitchenCommand>().HasMany(c => c.Lines).WithOne().HasForeignKey(l => l.CommandId).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<KitchenCommandLine>().HasKey(l => l.Id);
            modelBuilder.Entity<SaleJoinedTable>().HasKey(j => new { j.OrderId, j.TableId });
            modelBuilder.Entity<SaleCounter>().HasKey(c => c.IdEmpresa);
            modelBuilder.Entity<PrintJob>().ToTable("trabajos_impresion");
            modelBuilder.Entity<PrintJob>().HasKey(p => p.Id);
            modelBuilder.Entity<PrintJob>().HasOne<Order>().WithMany().HasForeignKey(p => p.OrderId).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<PrinterConfiguration>().HasKey(p => p.Id);
            modelBuilder.Entity<Producto>().HasKey(p => p.Id);
            modelBuilder.Entity<Rubro>().HasKey(r => r.Id);
            modelBuilder.Entity<SubRubro>().HasKey(s => s.Id);
            modelBuilder.Entity<Alicuota>().HasKey(a => a.Id);
            modelBuilder.Entity<ProductoCodigoContador>().HasKey(c => c.IdEmpresa);
            modelBuilder.Entity<StockProducto>().HasKey(s => s.Id);
            modelBuilder.Entity<StockMovement>().HasKey(s => s.Id);
            modelBuilder.Entity<ProductComponent>().HasKey(s => new { s.CompositeProductId, s.ComponentProductId });
            modelBuilder.Entity<Customer>().HasKey(c => c.Id);
            modelBuilder.Entity<CustomerCounter>().HasKey(c => c.CompanyId);
            modelBuilder.Entity<StockProducto>().HasIndex(s => new { s.IdProducto, s.IdSucursal }).IsUnique();
            modelBuilder.Entity<StockProducto>().HasOne(s => s.Producto).WithMany().HasForeignKey(s => s.IdProducto).OnDelete(DeleteBehavior.Cascade);
            modelBuilder.Entity<StockProducto>().HasOne(s => s.Sucursal).WithMany().HasForeignKey(s => s.IdSucursal).OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<Producto>()
                .HasIndex(p => new { p.IdEmpresa, p.Codigo })
                .IsUnique();

            modelBuilder.Entity<Producto>()
                .HasOne(p => p.Rubro)
                .WithMany()
                .HasForeignKey(p => p.IdRubro)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<Producto>()
                .HasOne(p => p.SubRubro)
                .WithMany()
                .HasForeignKey(p => p.IdSubRubro)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<Producto>()
                .HasOne(p => p.Alicuota)
                .WithMany()
                .HasForeignKey(p => p.IdAlicuota)
                .OnDelete(DeleteBehavior.Restrict);

            modelBuilder.Entity<ProductoCodigoContador>()
                .HasOne<Empresa>()
                .WithOne()
                .HasForeignKey<ProductoCodigoContador>(c => c.IdEmpresa)
                .OnDelete(DeleteBehavior.Cascade);

            modelBuilder.Entity<Usuario>()
                .HasOne(u => u.Empresa)
                .WithMany()
                .HasForeignKey(u => u.IdEmpresa);

            modelBuilder.Entity<Usuario>()
                .HasOne(u => u.Sucursal)
                .WithMany()
                .HasForeignKey(u => u.IdSucursal);

            modelBuilder.Entity<Usuario>()
                .HasOne(u => u.Rol)
                .WithMany()
                .HasForeignKey(u => u.IdRol);
        }
    }
}
