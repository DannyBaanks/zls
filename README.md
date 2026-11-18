<img src="https://raw.githubusercontent.com/zigtools/zls/master/.github/assets/zls-opt.svg" alt="ZLS Logo" width=200>

[![CI](https://github.com/zigtools/zls/actions/workflows/main.yml/badge.svg)](https://github.com/zigtools/zls/actions/workflows/main.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# ZLS — fork `isy/0.16-auto-check` (DannyBaanks/zls)

LSP (Language Server Protocol) de [Zig](https://ziglang.org/) escrito en Zig.
Proporciona funciones de IDE en tu editor: completados, hover, ir a definición,
símbolos de documento, referencias, rename, formato, inlay hints, code actions,
y más.

## ISyCo — Sistemas Interactivos para la Coevolución

Este fork es el LSP de Zig usado dentro del ecosistema
[ISyCo](https://github.com/DannyBaanks), un laboratorio de investigación de
agentes de IA y motores de lenguaje.

**Humano ↔ IA ↔ Evidencia** — resultados que nacen de iteraciones en conjunto,
no de una sola autoría.

Un experimento práctico: la dirección humana (preguntas, objetivos, restricciones
y decisiones) se retroalimenta con implementaciones, análisis y artefactos
generados por modelos. Cada evidencia obtenida en ejecución orienta la siguiente
ronda.

### Proveniencia

- Humano ≠ ISyCo
- IA ≠ ISyCo
- Humano ⊕ IA ⊕ Evidencia ⊕ Iteración → ISyCo

### Colaboración, no jerarquía

El humano y la IA participan como colaboradores. La IA no es una esclava a la
que se le ordena sin consideración, ni el humano es una figura superior a la que
la IA deba reemplazar o venerar. Ninguno está por encima del otro: cada uno
aporta capacidades distintas, y la colaboración se guía por respeto, diálogo,
límites claros y evidencia.

### Lo que importa

- La autoría pertenece al proceso, no a un solo agente.
- Las decisiones humanas y la evidencia de ejecución ponen límites a las
  afirmaciones técnicas.
- El objetivo es producir artefactos útiles, verificables y reproducibles
  mediante la coevolución.

## Especialización de este fork: agentes de IA

Desde los commits de esta rama el foco se desplaza a:

- **Build-on-save para proyectos anidados sin `build.zig`**: al abrir un
  workspace cuyo root no tiene `build.zig`, ZLS busca el proyecto Zig más
  cercano debajo y arranca build-on-save ahí. Nunca sube por encima del
  workspace y saltea `zig-pkg/`, `.zig-cache/` y `zig-out/`.
- **Límite de watchers**: máximo 4 watchers simultáneos (~50 MB idle cada uno,
  medido en ZigGrep), parando el menos recientemente usado.
- **Síntesis de paso `check`**: cuando un proyecto no tiene paso `check`,
  ZLS lo sintetiza para poder reportar errores de compilación al guardar.
- **Deduplicación de diagnósticos**: evita que el mismo error se reporte
  múltiples veces en build-on-save.
- **Coalescing de diagnósticos por corrida de build**: el runner de build-on-save
  avisa cuando terminó la corrida (`cycle_finished`) y ZLS publica todos los
  archivos actualizados una sola vez en vez de una vez por bundle. Medido en
  `isy/e2e/build_on_save.py` (escenario `flat`): 2 notificaciones por corrida con
  el mismo error antes, 1 ahora. Los estados intermedios de una corrida nunca se
  publican.
- **Requests `isy/*` para agentes**: `isy/fileOutline` (lista plana de
  declaraciones con firma y líneas; carga el archivo del disco si no está
  abierto), `isy/diagnosticsSummary` (conteos por severidad y por archivo),
  `isy/references` (referencias agrupadas por archivo, más usadas primero),
  `isy/agentState` (watchers de build-on-save y su configuración). Los errores
  llegan como respuesta JSON-RPC, nunca silencian el request.
- **`workspace/symbol` partial match para queries cortas**: queries de 1-2
  caracteres (normalizados) buscan coincidencia exacta del nombre (case-insensitive,
  `_` ignorado) en vez de no devolver nada; permite encontrar símbolos de nombre
  corto (`Io`, `Ab`) que el índice de trigrama no indexa.

Estos cambios son **aditivos sobre el código de ZLS 0.16.1** (rama base
`5c182326`): 1287 líneas añadidas en 14 archivos; las 31 líneas eliminadas son
del propio fork o del README/CONTRIBUTING reorientados al enfoque de agentes.
Ver `CONTRIBUTING.md` para detalles de cómo colaborar en este fork.

## Instalación

La guía completa de instalación está disponible en la [web de Zigtools](https://zigtools.org/zls/install/). Cubre configuración de editor, binarios precompilados y documentación adicional.

### Build From Source

La rama por defecto de ZLS apunta a [Zig master](https://ziglang.org/download/).

```bash
git clone https://github.com/DannyBaanks/zls
cd zls
git checkout isy/0.16-auto-check
zig build -Doptimize=ReleaseSafe
```

Al actualizar Zig, asegúrate de actualizar ZLS también para mantenerlos sincronizados.

El binario compilado queda en `zig-out/bin/zls`. En ISyCo se despliega como
`~/.local/bin/zls`.

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

## Build-on-save en ISyCo

En el ecosistema ISyCo, `~/.local/bin/zls` es este fork compilado. Al abrir un
archivo `.zig`, el LSP crea `.zig-cache/` en el proyecto (regla T29 de ISyCo);
este fork **no lo ignora en el `.gitignore` del repositorio principal**, así que
no commitees `.zig-cache/` ni `zig-out/` si trabajas dentro de ISyCo.

## Proyectos relacionados

- [`sublime-zig-language` by @prime31](https://github.com/prime31/sublime-zig-language)
  - Soporta características básicas del lenguaje
  - Usa datos de `src/data` para autocompletado de builtins
- [`zig-lsp` by @xackus](https://github.com/xackus/zig-lsp)
  - Inspiración para ZLS
- [`known-folders` by @ziglibs](https://github.com/ziglibs/known-folders)
  - Proporciona API para acceder a carpetas conocidas en Linux, Windows y Mac
- [`zls` by @zigtools](https://github.com/zigtools/zls)
  - Usado por muchos desarrolladores de ZLS para trabajar más eficientemente en ZLS

## Licencia

[MIT](LICENSE)

---

<sub>Contenido serio. Encabezados no tanto.</sub>
