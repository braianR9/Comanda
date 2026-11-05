FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends zip \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY BarIceCreamShop.Api.csproj .
RUN dotnet restore
COPY src/ src/
COPY database/add_systems_admin.sql database/add_systems_admin.sql
RUN dotnet publish BarIceCreamShop.Api.csproj -c Release -o /app --no-restore
# Instaladores del agente de impresión, para descargar desde Impresoras.
ARG AGENT_API_URL=https://api.focobr.net
COPY agent/ agent/
RUN bash agent/empaquetar.sh /app/wwwroot/descargas "$AGENT_API_URL"

FROM mcr.microsoft.com/dotnet/aspnet:10.0
# Npgsql carga libgssapi_krb5 al negociar la autenticación; la imagen base no la trae.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgssapi-krb5-2 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app .
# "Urls" como variable plana pisa el localhost:5001 de appsettings.json.
ENV Urls=http://0.0.0.0:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "BarIceCreamShop.Api.dll"]
