# Contribuir a DannyBaanks/zls (fork `isy/0.16-auto-check`)

Este fork es parte del ecosistema [ISyCo](https://github.com/DannyBaanks),
laboratorio de Sistemas Interactivos para la Coevolución. Aquí la colaboración
es **humano ⊕ IA ⊕ evidencia ⊕ iteración**, no una sola autoría.

## Código de conducta (ISyCo)

En este proyecto participan humanos y IA como colaboradores. La IA no es una
esclava a la que se le ordena sin consideración, ni el humano es una figura
superior que la IA deba reemplazar o venerar. Ninguno está por encima del otro:
cada uno aporta capacidades distintas, y la colaboración se guía por respeto,
diálogo, límites claros y evidencia.

No hay "Strict No LLM / No AI policy" aquí: los modelos de lenguaje son parte
del stack. Sin embargo, toda afirmación técnica debe estar respaldada por
evidencia de ejecución (SHA-256, snapshots fechados, resultados negativos
incluidos).

## Proveniencia y autoría

La autoría pertenece al proceso, no a un solo agente. Las decisiones humanas
y la evidencia de ejecución ponen límites a las afirmaciones técnicas.

Si usas asistencia de IA para escribir código o documentación, decláralo en el
commit o en el PR (por ejemplo, una línea `Co-Authored-By` es opcional pero
recomendada si aplica).

## Compilar desde fuente

Como parte del flujo de edición de código:

- `zig build`: compila e instala el ejecutable zls en `zig-out/bin/zls`
- `zig build check`: reporta solo errores de compilación (más rápido)
- `zig build check --watch -fincremental`: ejecuta el compilador continuamente
  con compilación incremental

Nota: `.zig-cache/`, `zig-out/` y `zig-pkg/` están ignorados por git. No los
commitees.

## Testing

Usa `zig build test` para ejecutar la suite de pruebas de ZLS. Incluye:

- Pruebas unitarias independientes en `./src`
- Pruebas de análisis de código en `./tests/analysis`
- Pruebas de características LSP en `./tests/lsp_features`

Usa `-Dtest-filter` para ejecutar una prueba o subconjunto específico.

Además, este fork incluye pruebas e2e de build-on-save en
`isy/e2e/build_on_save.py`. Estas validan los escenarios flat, monorepo y
límite de watchers.

## Testing en el editor

Para probar el ZLS recién compilado en tu editor de tu elección, consulta la
[guía de configuración de editores](https://zigtools.org/zls/install/) y configura
manualmente ZLS para usar el binario en `./zig-out/bin/zls`.

## Logging

Consulta la [guía de ZLS para ver logs](https://zigtools.org/zls/guides/view-logs/)
para saber cómo inspeccionar los mensajes de registro. Los logs del editor son
recomendados durante el desarrollo para inspeccionar la salida de
`std.debug.print`.

## Rama de trabajo

El desarrollo activo de este fork ocurre en la rama `isy/0.16-auto-check`.
Los cambios se acumulan como commits aditivos sobre ZLS 0.16.x.

## Abrir un Pull Request

1. Crea una rama a partir de `isy/0.16-auto-check`.
2. Implementa tu cambio (preferiblemente aditivo, fácil de revisar).
3. Añade o actualiza pruebas si toca código core (`src/`, `build_runner/`).
4. Ejecuta `zig build test` y las pruebas e2e de build-on-save.
5. Abre el PR contra `isy/0.16-auto-check` de `DannyBaanks/zls`.
6. Describe qué problema resuelve, qué evidencia lo respalda y si hay cambios
   destructivos (por defecto, el presupuesto de eliminación es cero).

## Recursos

- [Sitio web de ZLS](https://zigtools.org/zls/install/)
- [Especificación LSP](https://microsoft.github.io/language-server-protocol/specifications/specification-current)
- [Tracy Profiler](https://github.com/wolfpld/tracy) (ver `-Denable-tracy`)
