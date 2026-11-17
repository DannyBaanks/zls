<img src="https://raw.githubusercontent.com/zigtools/zls/master/.github/assets/zls-opt.svg" alt="ZLS Logo" width=200>

[![CI](https://github.com/zigtools/zls/actions/workflows/main.yml/badge.svg)](https://github.com/zigtools/zls/actions/workflows/main.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# ZLS — LSP de Zig optimizado para agentes de IA

Fork de [ZLS](https://github.com/zigtools/zls) que adapta el Language Server
Protocol de [Zig](https://ziglang.org/) para flujos de trabajo donde **un agente
de IA edita código y necesita diagnósticos fiables al guardar**, sin configuración
manual ni pasos de compilación extra.

> **Nota de divergencia:** este fork (`isy/0.16-auto-check`) se mantiene dentro
> del ecosistema ISyCo. Sus cambios son 100 % aditivos sobre ZLS 0.16.x y se
> centran en eliminar la fricción entre un agente y el compilador.

## Instalación

La guía completa de instalación está disponible en la [web de Zigtools](https://zigtools.org/zls/install/). Cubre configuración de editor, binarios precompilados y documentación adicional.

### Build From Source

```bash
git clone https://github.com/DannyBaanks/zls
cd zls
git checkout isy/0.16-auto-check
zig build -Doptimize=ReleaseSafe
```

El binario compilado queda en `zig-out/bin/zls`.

## Optimizado para agentes de IA

La razón de ser de este fork: un agente de IA no se detiene a configurar
build-on-save ni a lanzar `zig build check` después de cada edición. Necesita
que los errores de tipo y compilación lleguen solos. Estas son las mejoras:

- **Build-on-save sin configuración en proyectos anidados**: al abrir un
  workspace cuyo root no tiene `build.zig` (un monorepo, por ejemplo), ZLS
  busca el proyecto Zig más cercano debajo y arranca build-on-save ahí. Nunca
  sube por encima del workspace y saltea `zig-pkg/`, `.zig-cache/` y `zig-out/`.
- **Síntesis de paso `check`**: cuando un proyecto no define paso `check`,
  ZLS lo sintetiza para reportar errores de compilación al guardar.
- **Deduplicación de diagnósticos**: el mismo error no se reporta varias veces
  cuando un mismo archivo dispara varias rutas de compilación.
- **Límite de watchers**: como máximo 4 watchers simultáneos (~50 MB idle cada
  uno, medido en ZigGrep), parando el menos recientemente usado. Un agente que
  salta entre proyectos no acumula procesos de compilación.

### Por qué importa para agentes

ZLS estándar (zigtools) en un monorepo sin `build.zig` en la raíz solo reporta
errores de sintaxis: build-on-save nunca arranca. Las pruebas e2e de este fork
(`isy/e2e/build_on_save.py`) lo demuestran: los escenarios flat, monorepo y
límite de watchers pasan aquí y fallan en ZLS 0.16.1 estándar.

## Features

ZLS soporta la mayoría de las características del lenguaje, incluyendo soporte
simple para funciones con tipo, `using namespace`, captura de payload, resolución
de tipos, paquetes personalizados, `cImport` y otros. El soporte para `comptime`
y análisis semántico es Work-in-Progress.

Las siguientes características LSP están soportadas:

- Completados
- Hover
- Ir a definición/declaración
- Símbolos de documento
- Buscar referencias
- Rename de símbolo
- Formateo usando `zig fmt`
- Resaltado de tokens semánticos
- Inlay hints
- Code actions
- Rangos de selección
- Regiones de plegado

## Notas

- Los cambios de este fork son aditivos sobre ZLS 0.16.x; la base sigue siendo
  ZLS de zigtools.
- Ver `CONTRIBUTING.md` para la política del fork (colaboración humano-IA
  basada en evidencia) y cómo colaborar.

## Proyectos relacionados

- [`zls` by @zigtools](https://github.com/zigtools/zls)
  - El LSP de Zig original del que parte este fork
- [`sublime-zig-language` by @prime31](https://github.com/prime31/sublime-zig-language)
  - Soporta características básicas del lenguaje
  - Usa datos de `src/data` para autocompletado de builtins
- [`zig-lsp` by @xackus](https://github.com/xackus/zig-lsp)
  - Inspiración para ZLS
- [`known-folders` by @ziglibs](https://github.com/ziglibs/known-folders)
  - Proporciona API para acceder a carpetas conocidas en Linux, Windows y Mac

## Licencia

[MIT](LICENSE)