FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY BarIceCreamShop.Api.csproj .
RUN dotnet restore
COPY src/ src/
RUN dotnet publish BarIceCreamShop.Api.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app .
# "Urls" como variable plana pisa el localhost:5001 de appsettings.json.
ENV Urls=http://0.0.0.0:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "BarIceCreamShop.Api.dll"]
