# Windows Server – Directorio Activo (empresa.local)

Práctica de administración de sistemas en Windows Server donde se realiza la instalación del Directorio Activo y la creación automática de la estructura de la empresa mediante un script en PowerShell.

## Objetivo de la práctica
- Instalar Active Directory mediante el Administrador del Servidor.
- Crear el dominio **empresa.local**.
- Automatizar la creación de la estructura del dominio a partir de archivos CSV.
- Crear unidades organizativas, grupos y usuarios de forma centralizada.

## Estructura creada en Active Directory
- **OU raíz**: Empresa
- **OU por departamento** (según `departamentos.csv`)
- **Grupo de seguridad GLOBAL** por cada departamento
- **Usuarios** creados a partir de `empleados.csv`
  - Login con formato `nombre.apellido`
  - Contraseña por defecto: `aso2025.`
  - Cambio de contraseña obligatorio en el primer inicio de sesión
- Cada usuario pertenece al grupo de su departamento

## Archivos del repositorio
- `CrearEstructuraAD.ps1` → Script PowerShell de creación automática
- `departamentos.csv` → Departamentos de la empresa
- `empleados.csv` → Empleados de la empresa
- `README.md` → Documentación de la práctica

## Requisitos
- Windows Server 2019/2022
- Dominio configurado: **empresa.local**
- Ejecutar el script en el Controlador de Dominio
- PowerShell ejecutado como Administrador

## Ejecución del script
Copiar los archivos en una carpeta (por ejemplo `C:\AD_Practica`) y ejecutar:

```powershell
cd C:\AD_Practica
Set-ExecutionPolicy -Scope Process Bypass
.\CrearEstructuraAD.ps1
