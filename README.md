# Promoción Cultural · Complejo Almafuerte

Repositorio único de la aplicación de gestión cultural y de su extensión de búsqueda de PPL.

## Estructura

- `web/`: aplicación estática publicada en Cloudflare Workers.
- `database/`: esquema inicial de Supabase y actualizaciones SQL, en orden numérico.
- `extension/`: extensión de Chrome **Cultura · Búsqueda PPL**.

## Publicar la aplicación web

Subir el contenido de `web/` al proyecto de Cloudflare que publica la aplicación.

La URL y clave pública de Supabase están configuradas en `web/app.js`. Nunca se debe guardar una clave `service_role`, contraseñas institucionales ni archivos `.env` en el repositorio.

## Base de datos

Para una instalación nueva, ejecutar `database/supabase.sql` en Supabase. Para una instalación ya existente, aplicar los archivos `database/actualizacion_XX.sql` que todavía no se hayan ejecutado, respetando el orden.

## Extensión Chrome

1. En Chrome abrir `chrome://extensions`.
2. Activar **Modo desarrollador**.
3. Pulsar **Cargar extensión sin empaquetar** y elegir la carpeta `extension/`.
4. Configurar las credenciales institucionales desde el icono de la extensión.

La extensión permite que Buscar PPL consulte el sistema institucional sin que el navegador muestre esas ventanas.
