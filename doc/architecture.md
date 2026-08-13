# Arquitectura de `remind`

Documento de decisiones. Registra **por qué** el proyecto está construido así,
no cómo se usa — para eso están los README de cada paquete.

---

## 1. El problema

El objetivo es poder **embeber funcionalidad de recordatorio en aplicaciones
propias**: hora, día de la semana, varios días, fechas específicas y ubicación.
No construir una app de despertador.

Esa distinción determina casi todo lo demás.

## 2. Qué ya existe (investigación, agosto 2026)

| Paquete | Qué resuelve | Recurrencia |
|---|---|---|
| [`alarm`](https://pub.dev/packages/alarm) | iOS+Android, audio nativo, foreground service + AlarmManager. ~10.8k descargas/semana | **No.** Su FAQ dice que las alarmas periódicas son viables en Android pero no en iOS; hay que reprogramar a mano |
| [`flutter_alarmkit`](https://pub.dev/packages/flutter_alarmkit) | AlarmKit de Apple (iOS 26). Suena con Do Not Disturb y app terminada, Live Activity | Sí, por días de semana — pero **solo iOS 26+**, sin Android |
| [`flutter_local_notifications`](https://pub.dev/packages/flutter_local_notifications) | Estándar de facto para notificaciones programadas | `DateTimeComponents.dayOfWeekAndTime`, con **techo de 64 notificaciones pendientes en iOS** |
| [`android_alarm_manager_plus`](https://pub.dev/packages/android_alarm_manager_plus) | AlarmManager crudo | Solo Android |
| [`rrule`](https://pub.dev/packages/rrule), `teno_rrule` | Recurrencia RFC 5545 en Dart | Sí, pero desconectado de la entrega |

**Conclusión:** la capa de *entrega* está bien resuelta. Lo que no existe es la
capa de *programación* que hay encima. Las apps open source revisadas
([Awake](https://github.com/adeeteya/Awake-AlarmApp),
[clockee](https://github.com/GiddyNaya/clockee), etc.) reimplementan todas el
mismo pegamento: persistir, calcular la próxima ocurrencia, reprogramar en boot,
manejar snooze.

## 3. Decisión: núcleo en Dart puro

**El core no es una librería de cálculo, es el cerebro.** La analogía es un
termostato: la lógica que decide *"bajó de 20°, hay que encender"* no necesita
saber nada de relés ni voltajes. El relé sí toca el hardware.

El core hace cuatro cosas, ninguna de las cuales toca el sistema operativo:

1. **Modelar** qué es un recordatorio: disparadores, condiciones, acción, estado.
2. **Resolver ocurrencias** — dada una regla y una zona horaria, ¿cuáles son los
   próximos N instantes?
3. **Reconciliar** el estado deseado contra el registrado en el SO, y emitir el
   diff. *(pendiente, ver §8)*
4. **Reaccionar** a boot, resume, cambio de zona horaria y cambio de hora del
   sistema, re-reconciliando.

### Por qué importa que sea Dart puro

- **Testeable sin dispositivo.** El escenario *"usuario en Santiago, alarma
  martes 07:00, cruza el cambio de horario de septiembre"* se verifica en
  milisegundos. Si esa lógica vive dentro de un plugin, se prueba a mano en un
  teléfono — es decir, no se prueba.
- **Mantenimiento viable.** No hay que competir contra AlarmKit ni contra los
  OEM (Samsung mata alarmas vía "Deep Sleeping Apps" aun con
  `exactAllowWhileIdle`).
- **Sin fricción de permisos.** El paquete central nunca declara permisos.

El proyecto **completo** sí es una familia de plugins; lo que es Dart puro es el
paquete central.

## 4. Decisión: adaptadores en paquetes separados

No es purismo. Si el código de geofencing viviera en el paquete principal, el
manifest merger de Android inyectaría `ACCESS_BACKGROUND_LOCATION` en **toda**
app que dependa de él — incluidas las que solo quieren recordatorios por hora. Y
esas apps tendrían que justificar ante Google Play un permiso que no usan.

`ACCESS_BACKGROUND_LOCATION` exige declaración escrita **y video demo** con
revisión manual. Es fricción que solo debe pagar quien realmente usa ubicación.

## 5. Decisión: `alarm` es una entrega, no una intención

Al principio el dilema parecía ser "¿el paquete se llama alarm o reminder?".
Están en niveles distintos:

- **Reminder** es la *intención*: "quiero acordarme de X bajo la condición Y".
- **Alarm** / **notification** son *entregas*: cómo se manifiesta.

Por eso la raíz de la familia es `remind` y `alarm` aparece solo en el nombre de
un adaptador. Efecto secundario útil: el paquete central nunca dice "alarma", lo
que lo mantiene fuera de la conversación de `USE_EXACT_ALARM` —
[permiso restringido](https://support.google.com/googleplay/android-developer/answer/16558241)
a apps cuya funcionalidad principal es reloj, alarma o calendario, con revisión
manual de Google Play. Un recordatorio embebido normalmente **no** califica.

## 6. Decisión: disparadores generativos vs reactivos

La asimetría no es de diseño, la impone el sistema operativo:

| | **TimeTrigger** | **LocationTrigger** |
|---|---|---|
| Naturaleza | Generativo | Reactivo |
| ¿Se puede enumerar? | Sí — "dame las próximas 10" | **No** — nadie puede listar las próximas 10 veces que alguien entrará a un edificio |
| Cómo funciona | Se registra un instante futuro | Se registra una región; el SO despierta |
| Presupuesto | iOS: 64 notificaciones pendientes | iOS: **20 regiones**; Android: ~100 |

Nadie "vigila" nada activamente. Un loop que consulte el GPS en background lo
mata la batería y lo mata el SO. Se registran condiciones y el sistema avisa.

Los disparadores de un recordatorio se combinan con **OR**, y por eso son una
lista simple en vez de un álgebra de combinadores: el OR es implícito.

## 7. Decisión: condiciones temporales vs ambientales

El AND entre tiempo y lugar es la diferenciación real del proyecto, y **solo se
puede resolver en Dart**: no existe API de SO para *"cuando llegue a la oficina,
pero solo entre semana"*.

En vez de un álgebra simétrica AND/OR sobre disparadores — que sería incorrecta,
porque un `LocationTrigger` no se puede enumerar — el modelo separa:

> **Trigger** = cuándo mirar. **Condition** = si actuar.

Y las condiciones se dividen por *cuándo se pueden evaluar*:

- **`TemporalCondition`** — función pura de un instante. El motor la evalúa
  mientras enumera y descarta las ocurrencias que fallan. No involucra al
  dispositivo.
- **`AmbientCondition`** — depende de estado que aún no existe (la ubicación).
  Viaja con la ocurrencia y se evalúa al momento de disparar.

`partitionCondition` hace ese corte. Regla de corrección importante:

- Las **conjunciones distribuyen**: en `AllOf([temporal, ambient])` la mitad
  temporal poda de inmediato.
- Las **disyunciones y negaciones no**: en `AnyOf([temporal, ambient])` una
  mitad temporal falsa no prueba nada, porque la ambiental todavía puede
  cumplirse. Esos árboles se difieren enteros.

Podar disyunciones de forma temprana descartaría ocurrencias válidas. Es una
restricción de corrección, no una optimización pendiente.

## 8. Decisión: nunca sumar `Duration` entre ocurrencias

El bug clásico. Comprobado contra la base IANA:

```
America/Santiago, 07:00 diario, cambio de horario de septiembre 2026

  2026-09-04 07:00 -0400
  2026-09-05 07:00 -0400
  2026-09-06 07:00 -0300   <- se mantuvo el reloj de pared, se movió el offset
```

`previous + Duration(days: 1)` suma exactamente 24 horas absolutas. Cruzando la
transición, la alarma de las 07:00 pasa a ser de las 06:00 — y se queda así.

El motor **siempre** reconstruye desde campos de calendario (año, mes, día +
hora de pared). Hay un test que verifica explícitamente que la aritmética
ingenua produciría un resultado distinto, para que la prueba no se vuelva vacía.

### Casos borde, verificados contra `package:timezone`

- **Hora borrada** (salto adelante): `2026-03-08 02:30` no existe en Nueva York.
  Política por defecto `shiftForward` → dispara a las 03:30 y marca la
  ocurrencia con `DstAnomaly.gapShifted`. Alternativa `skip` para casos donde
  disparar tarde sería peor que no disparar (intervalo de medicación, apertura
  de mercado).
- **Hora duplicada** (retroceso): `2026-11-01 01:30` ocurre dos veces. Se
  resuelve al **primer** instante y se marca
  `DstAnomaly.ambiguousResolvedEarly`.

Ambas anomalías se **reportan** en vez de esconderse: es la clase de sorpresa
que el usuario final nota y le achaca a la app, así que la aplicación debe poder
avisar.

## 9. Decisión: desconocido no es falso

`evaluateCondition` devuelve tres valores — `holds`, `fails`, `undetermined` —
no dos.

Una condición de geocerca evaluada sin fix de ubicación no tiene respuesta
booleana honesta. Colapsarla a `false` silenciaría recordatorios que el usuario
sí pidió: el peor modo de falla posible para esta librería.

La composición sigue lógica trivaluada de Kleene, así que el desconocido solo se
propaga cuando todavía puede cambiar la respuesta. Un `AllOf` con una rama que
falla, falla — y le ahorra al llamador una consulta de GPS que no necesitaba.

## 10. Pendiente

### Reconciliador

La pieza que justifica el paquete y que aún no está. Mantiene dos estados:

- **Deseado** — los recordatorios del usuario.
- **Real** — lo que efectivamente está registrado en el SO.

Calcula el diff y emite comandos. Resuelve el techo de 64 de iOS: no se
registran 40 recordatorios semanales (= 280 ocurrencias), se registra la ventana
próxima y se re-materializa cuando se consume. El mismo mecanismo prioriza
geocercas por cercanía contra el presupuesto de 20 de iOS.

### Otros

- Puertos de persistencia (`ReminderStore`) y de entrega (`ReminderBackend`).
- Ganchos de ciclo de vida: boot, resume, cambio de zona horaria.
- Snooze y "saltar la próxima".
- `RRuleTrigger` sobre RFC 5545 (`package:rrule`) para reglas que
  `DateListTrigger` no cubre con elegancia.
- Adaptadores: `remind_notifications`, `remind_alarm`, `remind_geofence`.

## 11. Convenciones

- **Monorepo** con pub workspaces nativos (Dart 3.6+, glob `code/*` en 3.11+).
  Un solo `dart pub get` en la raíz resuelve todo.
- **Idioma**: API pública, doc comments y README en inglés — pub.dev es un
  catálogo internacional. Este documento de arquitectura, en español.
- **Lints estrictos** compartidos desde la raíz, con
  `public_member_api_docs` activo: es una librería pública y la documentación de
  la API no es opcional.
