# Looper

Un sintetizador looper de bolsillo para Android e iOS. Cuatro bancos de dieciséis
pads, grabación de sonidos propios con el micrófono y una sesión que se puede
grabar y exportar. Funciona sin conexión: no hay cuentas, ni servidor, ni
sincronización. Todo el audio vive en el dispositivo.

El nombre es provisional.

## La idea

Lo más parecido a esto es un controlador MIDI con cerebro propio: sonidos de
fábrica, efectos, tus grabaciones encima y un botón de grabar la sesión. Se usa
para ir levantando una base dejando loops corriendo mientras trabajas, no para
abrir un editor y peinar formas de onda.

Está pensado para alguien que quiere hacer música sin saber producción: graba
con el micrófono lo que tenga a mano, lo asigna a un pad y arma una base por
capas en menos de un minuto.

## Principios de diseño

- **Todo a un dedo de distancia.** Durante una sesión no debería abrirse ni un
  desplegable. Tempo, tono, volumen, efectos y sincronía viven en la pantalla
  principal. Los menús quedan para configurar la app, no para tocarla.
- **Una mano, en vertical.** Transport abajo en el arco del pulgar, franja de
  mando justo encima, grilla al centro.
- **El estado se lee por color y movimiento, nunca por texto.** Qué suena, qué
  está en loop y qué está vacío se ve de un vistazo.
- **Libre por defecto.** Cada loop corre a su propio largo. Sincronizar al tempo
  es una decisión por loop, nunca una imposición.
- **Se aprende tocando.** Cero onboarding: al abrir por primera vez los bancos A
  y B ya vienen cargados y suenan.

## Los gestos de la grilla

El gesto decide cómo suena un pad; el pad no guarda ningún «modo».

| Gesto | Qué hace |
|-------|----------|
| Un toque | Dispara el sonido. Tocar al ritmo suena a ese ritmo: cada golpe corta el anterior del mismo pad |
| Toque en un pad que está en loop | Lo apaga |
| Mantener pulsado | Lo deja en loop, con una vibración corta al arrancar |
| AJUSTAR y luego un pad | Abre la hoja del pad: cambiar sonido, sincronía, largo y vaciar |
| AJUSTAR y luego ROLL | Cambia la división del roll entre corchea y semicorchea |

**Deshacer** vive arriba, junto a la biblioteca, y solo aparece cuando hay algo
que retirar. Guarda hasta veinte pasos atrás de lo que se puede perder de
verdad: vaciar un pad, cambiarle el sonido y borrar un patrón. Los mandos
continuos —volumen, tono, acento— no entran: se deshacen moviéndolos otra vez, y
una instantánea por fotograma de arrastre enterraría lo que sí cuesta rehacer.
Al borrar un sonido de la biblioteca se va también su fichero, así que ahí el
historial se limpia entero en vez de ofrecer una vuelta atrás rota.

AJUSTAR es el único estado modal del instrumento y dura un solo toque: al
encenderlo la grilla entera se enciende en fósforo para avisar de que el
siguiente toque no va a sonar. El mismo trato vale fuera de la grilla: armado,
el siguiente botón del transport se configura en vez de usarse.

**El roll** se mantiene pulsado y repite el pad que toques. Su división se lee
en el propio botón (ROLL 1/8, ROLL 1/16) y cambiarla mientras rueda retima el
fill sobre la marcha.

**Silenciar y solo** comparten botón: un toque silencia el pad elegido, mantener
pulsado lo pone en solo. El solo no escribe nada en los demás pads —manda
mientras está puesto y al quitarlo vuelven exactamente los silencios que
hubieras puesto a mano—. Con un solo activo el botón lo dice, aunque el pad esté
en otro banco, y tocarlo lo levanta.

## El secuenciador de dieciséis pasos

Un patrón es un compás partido en dieciséis pasos. Cada paso guarda las notas
que suenan en él —ninguna, una o varias a la vez— y un paso vacío es un
silencio. Una sesión lleva dieciséis patrones independientes.

Como la grilla tiene dieciséis pads, **el pad número N es el paso número N**:
cada pad estrena unas luces en la esquina opuesta, que se encienden flojas si
ese paso tiene notas y fuerte cuando el cabezal pasa por encima. Son **una por
sonido**, hasta cuatro: un paso con bombo y palma enciende dos, así que se ve
de un vistazo dónde hay una sola voz y dónde hay un acorde. El paso que estás
editando las lleva huecas, y conserva una aunque esté vacío para que elegir una
casilla en silencio se vea. El patrón se lee en la propia grilla, sin robarle
sitio a nada.

Un compás se queda corto enseguida, y la solución es la de siempre —las Volca,
la Circuit y el FM-1 encadenan patrones en vez de estirarlos—: el botón de
**compases** de la barra pone a sonar P1…PN seguidos (1, 2, 4, 8 o 16
compases). La grilla va siguiendo al patrón que suena, así que las luces
siempre cuentan la verdad.

Hay dos maneras de escribir, las mismas que trae una caja de ritmos:

- **En vivo (REC):** primero suena **un compás de cuenta atrás** —cuatro clics,
  con acento en el uno, aunque el metrónomo esté apagado— y solo entonces
  empieza a escribir, desde el paso uno. Cada pad que tocas cae en el paso
  actual y el cabezal avanza solo. Los pads que toques casi a la vez se quedan
  en el mismo paso, así que un acorde sigue siendo un acorde. SILENCIO avanza
  dejando el paso vacío. Volver a pulsar REC durante la cuenta la cancela.
- **Dirigida:** mantén pulsado un pad para elegir *su* paso; a partir de ahí
  cada pad pone o quita su nota en ese paso y nada avanza hasta que tú quieras.

Cada paso guarda además **con qué fuerza pega**. Con un paso elegido, la barra
del secuenciador cambia el texto de estado por un deslizador de ACENTO, y los
pads dibujan esa fuerza como una barra en su borde inferior: dieciséis barras
seguidas se leen como la dinámica del compás escrita. Un patrón donde todos los
golpes pegan igual suena a máquina; esto es lo que lo devuelve a una mano.

El **swing** vive en la misma barra, como tres sensaciones con nombre en vez de
un número: RECTO, SUAVE y TRESILLO. Es la regla que inventó el MPC-60 en 1988 —
retrasar solo las semicorcheas pares— y tiene una propiedad que conviene no
romper: cada par sigue sumando lo mismo, así que las negras no se mueven y ni el
metrónomo ni un bucle de una negra o más se enteran de que hay swing puesto. El
swing viaja con la sesión, como el tempo.

El patrón corre sobre el mismo reloj de semicorcheas que los loops
sincronizados, así que nunca se separa de ellos, y cambiar el tempo no lo corta.

## Las tres capturas, y por qué ninguna se llama «grabar»

Aquí se captura en tres sitios distintos, y llamarlos a todos *grabar* era la
receta para no entender ninguno. Cada uno usa la palabra que ya usan las
máquinas del oficio, y ninguna palabra se repite:

| | **SAMPLEAR** | **REC** | **EXPORTAR** |
|---|---|---|---|
| Icono | Micrófono | Punto láser | Flecha de compartir |
| De dónde | Del micrófono | De tus dedos | De la salida del mezclador |
| Qué guarda | Audio: un WAV en la biblioteca | Decisiones: qué pads suenan en cada paso | Audio: un WAV para mandar |
| Dónde vive | Pantalla propia | Barra del secuenciador | Transport |
| ¿Suena la app mientras? | No, y a propósito | Sí | Sí |
| Dura | 10 s como mucho | Un compás | Lo que dure la sesión |

El **punto láser es del secuenciador y de nadie más**: en cualquier máquina de
este tipo ese icono significa «estoy escribiendo el patrón». Por eso exportar
lleva la flecha de compartir y no un círculo. El color es el magenta de la
marca, no el rojo de fábrica: el rojo estaba en tres botones a la vez y por eso
había dejado de significar algo.

Samplear no puede sonar nada porque el micrófono nunca se abre mientras hay
reproducción: se acaba el sangrado del altavoz al micro y, de paso, los dos
motores de audio no se pelean por la sesión de audio del sistema. Exportar sí
convive con todo, porque no oye la habitación: oye el mezclador.

## Los cuatro bancos

| Banco | Contenido |
|-------|-----------|
| A · Kit | Batería acústica, bajo, acordes y dos voces |
| B · Techno | Cuatro bombos duros y una fila de líneas acid tipo 303 |
| C · Mías | Empieza vacío; cada grabación nueva cae aquí |
| D · Libre | Para montar variaciones o apartar los sonidos de un tema |

Los loops de un banco siguen corriendo cuando cambias a otro. La pestaña de un
banco con loops activos lleva una barra encendida abajo.

## El kit de fábrica se sintetiza en el dispositivo

No hay ni un sample binario en el repositorio. Las 32 voces se calculan con
código en `lib/audio/voices.dart` —osciladores, ruido filtrado, envolventes y
saturación— y se escriben como WAV en un isolate la primera vez que arranca la
app.

El bombo hardtechno es una onda seno barriendo de 190 a 46 Hz a través de un
saturador. La fila acid es una sierra pasando por un filtro paso bajo resonante
cuyo corte cae durante la nota, que es de donde sale el chillido característico.

La consecuencia práctica es que el repositorio no pesa nada, no hay licencias de
terceros sobre el audio, y retocar un sonido es cambiar unos números.

## La identidad

El suelo es berenjena, no gris oscuro: el violeta de la marca bajado al 11 % de
luminosidad, con un 54 % de saturación intacto. Es lo que deja la luz UV al
pegar en una pared, y por eso la app parece estar dentro del aparato en vez de
sobre una hoja. La profundidad se construye subiendo esa escalera —pozo, sala,
panel, alto, línea— y nunca tirando un negro translúcido por encima.

Los cuatro colores de familia recorren un solo arco de matiz: fósforo para la
percusión, menta para la voz, cielo para el tono y UV para la textura. El
fósforo hace además de acento de marca, y el láser sustituye al rojo en el REC
del secuenciador. El rojo se fue porque estaba en tres botones a la vez.

Dos tipografías variables, y los ejes se manejan desde un solo sitio
(`lib/core/type.dart`):

| Cara | Eje | Para qué |
|------|-----|----------|
| Archivo | `wdth` 100–125, `wght` 400–900 | La voz: nombres, títulos y texto corrido |
| Martian Mono | `wdth` 75–87, `wght` 500–700 | Los datos: tempo, pasos, direcciones de pad y las micro-etiquetas del transport |

El peso se pide siempre por `fontVariations` y nunca por `fontWeight`, para que
el motor interpole el eje en vez de fingir una negrita encima de otra.

Ningún color vive fuera de `lib/core/palette.dart`, y ningún `TextStyle` se
escribe a mano fuera de `type.dart`. El logo (`tool/make_icon.py`) y los fondos
de arranque de Android e iOS salen de los mismos valores.

Identidad completa: artifact «Identidad Looper»,
https://claude.ai/code/artifact/e88abf13-2695-40e4-85e7-9f3743adc153

## Estructura

```
lib/
  core/         Paleta, tipografía de marca, familias de sonido y límites
  domain/       Modelos inmutables: Sound, PadConfig, Bank, Session, Pattern
  data/         Almacenamiento local, biblioteca, sesiones, kit de fábrica
  audio/        Síntesis, WAV, motor SoLoud, reloj, micrófono y mezcla
  state/        SessionController y Sequencer
  ui/pads/      Grilla, bancos, tempo, franja de mando, barra del secuenciador
  ui/sampler/   Samplear con el micrófono y revisar lo capturado
  ui/library/   Biblioteca y editor de sonido
  ui/sessions/  Lista de sesiones
  ui/common/    Lo que usan varias pantallas, como la forma de onda
```

Los nombres del código siguen los de la interfaz: `MicRecorder` y
`SamplerScreen` para samplear, `Sequencer` para el REC del patrón y
`MixdownRecorder` para exportar. Ninguna clase se llama «record» a secas.

El estado es inmutable: cambiar un pad devuelve una sesión nueva en lugar de
mutar la existente.

## Motor de audio

- **Reproducción:** [flutter_soloud](https://pub.dev/packages/flutter_soloud),
  nativo por FFI, con los sonidos descomprimidos en memoria para que no haya
  retardo entre tocar y oír.
- **Loops libres:** SoLoud los repite de forma nativa a su largo natural.
- **Loops sincronizados:** un reloj propio de semicorcheas los redispara para que
  las capas caigan juntas. Cambiar el tempo no corta nada.
- **Micrófono:** [flutter_recorder](https://pub.dev/packages/flutter_recorder)
  captura en float de 32 bits —el único formato del que se puede leer el nivel
  de entrada— y la toma se guarda como WAV de 16 bits, el mismo formato que el
  kit de fábrica. Antes de guardarla se corta a diez segundos y se normaliza a
  0,9 para que suene al nivel del resto.
- **Exportar la toma:** captura de la salida del mezclador a WAV.

## Puesta en marcha

```
flutter pub get
flutter run
```

Requiere Flutter 3.44 o superior. La primera ejecución tarda unos segundos de
más: está sintetizando el kit.

Para las pruebas:

```
flutter test
```

## Estado

Funcionando:

- Los cuatro bancos con sus pestañas y el kit de fábrica generándose solo
- Paso de tempo con aceleración al mantener pulsado, y TAP
- Grilla con disparo, loop, silenciar y solo
- Franja de mando con las solapas de sonido, efectos y loop
- Persistencia de sesiones y biblioteca
- Grabar con el micrófono, escuchar la toma y guardarla: cae en el primer pad
  libre del banco C y ya suena
- Gestos de la grilla: toque dispara, mantener deja en loop, AJUSTAR abre la
  hoja del pad
- Biblioteca con editor: recorte, tono, volumen, familia, borrar e importar WAV
- Lista de sesiones: abrir, crear, renombrar, duplicar y borrar
- Grabar la interpretación y compartir el WAV
- Roll manteniendo pulsado, en corcheas o semicorcheas
- Metrónomo con acento en el uno del compás
- Secuenciador de dieciséis pasos con dieciséis patrones, grabación en vivo y
  edición paso a paso

- Efectos de directo sobre la salida: filtro con resonancia, eco y drive,
  en la franja de mando
- Cadena de patrones de 1 a 16 compases
- Deshacer hasta veinte pasos: vaciar pad, cambiar sonido y borrar patrón
- Swing por sesión: recto, suave o tresillo
- Acento por paso, con barra en el pad y deslizador en la barra
- Compás de cuenta atrás antes de escribir el patrón
- Licencias de código abierto desde la lista de sesiones
- Logo e iconos generados por código (`tool/make_icon.py`)

Pendiente:

- Elegir licencia del repositorio
- Verificar en el móvil la cuenta atrás del REC y las divisiones del roll

## Fuera de alcance

Colaboración, nube y cuentas, tienda de sonidos, MIDI externo, automatización
por pistas y mezclador multipista completo.

## Notas de compilación

Las versiones de Android están fijadas a propósito:

- AGP 8.7.3 y Kotlin 2.1.0. Con AGP 9, `file_picker` omite el plugin de Kotlin
  esperando el integrado de AGP, que la plantilla de Flutter desactiva, y sus
  clases nunca se compilan.
- `compileSdk = 36`.
- `permission_handler` en la rama 12, porque la 13 exige compileSdk 37.
- `file_picker` 11 con `share_plus` 12, por un choque de versiones de `win32`.

## Licencia

Pendiente de decidir. Las dependencias son todas permisivas (zlib, MIT, Apache
2.0 y BSD-3) y el audio de fábrica se genera con código propio.

El único material de terceros son las dos tipografías, Archivo y Martian Mono,
ambas bajo SIL Open Font License 1.1. La OFL pide viajar con las fuentes que
cubre: sus textos están en `assets/fonts/` y `main()` los registra en
`LicenseRegistry`, así que salen en la pantalla de licencias de la app.
