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
| AJUSTAR y luego una escena | La vacía |
| AJUSTAR y luego SEQ | Abre el largo de cada pista del patrón |
| Mantener EXPORTAR | Saca una pista por familia, en cuatro pasadas |

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

## Qué le hace un pad a otro

Dos ajustes en la hoja del pad, y entre los dos cubren lo que un groovebox
llama modos de pista.

**Golpes** decide qué le pasa al sonido anterior *del mismo pad*:

| Modo | Qué hace |
|------|----------|
| Corte | El golpe nuevo mata al anterior. Teclear rápido suena a redoble, y por eso es el de fábrica |
| Capas | Se apilan. Ocho toques en una campana dejan ocho campanas sonando |
| Una vez | Entra entero y no se deja interrumpir, ni por sí mismo |

Las voces apiladas dejan de ser la voz actual del pad, pero quedan aparcadas
para que PARAR las alcance: una voz que nadie sujeta es una voz que el botón de
pánico no puede parar.

**Grupo** es la convención del MPC: dos pads del mismo grupo no pueden sonar a
la vez, porque las cosas que representan tampoco —un charles abierto y uno
cerrado son un solo trozo de metal—. El pad que entra calla a los demás de su
grupo *antes* de sonar él. **Los bucles no se tocan:** un bucle es la decisión
de dejar algo corriendo, y un toque en el pad de al lado no es la decisión de
deshacerla. Y un pad nunca se corta a sí mismo por el grupo: eso lo decide su
modo de golpe, y mezclar las dos reglas dejaría un pad de un grupo sin poder
apilarse consigo mismo.

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

La cadena se queda corta en cuanto un tema tiene partes: siempre P1…PN, siempre
un compás cada uno. **Manteniendo pulsada esa misma pastilla** se abre la
canción, que es la respuesta larga a la misma pregunta —qué suena después de
este compás—: cualquier patrón, las veces que quieras, en el orden que quieras
(P1×2 · P3 · P2×4). Por eso la canción **no tiene interruptor propio**, entra
como una posición más del anillo de la pastilla: 1, 2, 4, 8, 16, canción. Dos
mandos para una pregunta acaban contradiciéndose.

La canción se escribe **desde el patrón que tengas en la rejilla**, compás a
compás: AÑADIR P3 lo pone al final, y para el siguiente vuelves a la rejilla.
Reordenar son dos flechas, nunca un arrastre: en una hoja de móvil un arrastre
pelea con el desplazamiento de la propia hoja. Mientras suena, la línea de
estado deja de contar pasos y cuenta compases de la canción, que es lo que
quieres saber a los cuatro minutos de tema. Y la canción es una lista de
*compases*, no una línea de tiempo en segundos: por eso corre sobre el mismo
reloj de semicorcheas que todo lo demás.

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

Además del acento, cada paso guarda otras tres cosas, y **un solo deslizador
sirve para las cuatro**: tocar su rótulo cicla entre ACENTO, PROB, MICRO y
RATCHET, así que editar un paso nunca le cuesta a la pantalla más de una fila.

- **Probabilidad**: cuántas veces de cada diez suena ese paso. Es lo que hace
  que un patrón deje de repetirse idéntico. Un paso al 100 % no tira el dado
  siquiera, así que un patrón sin tocar suena igual pase lo que pase con el azar.
- **Micro-timing**: adelanta o atrasa el golpe media semicorchea sin mover el
  resto. Adelantar es lo caro de implementar —hay que enviar el paso un pulso
  antes, montado sobre el anterior— y por eso el secuenciador mira siempre un
  pulso por delante.
- **Ratchet**: parte el paso en 2, 3 o 4 golpes iguales. El motor ya existía en
  el ROLL; aquí se fija a un paso del patrón.

**Copiar.** COPIAR en la hoja de un pad lo levanta —sonido y ajustes— y arma la
grilla: el siguiente pad que toques lo recibe. Mantener pulsado el número de
patrón (P1) copia el patrón entero; luego vas al patrón de destino y PEGAR lo
suelta ahí. Las dos cosas pasan por deshacer.

El **swing** vive en la misma barra, como tres sensaciones con nombre en vez de
un número: RECTO, SUAVE y TRESILLO. Es la regla que inventó el MPC-60 en 1988 —
retrasar solo las semicorcheas pares— y tiene una propiedad que conviene no
romper: cada par sigue sumando lo mismo, así que las negras no se mueven y ni el
metrónomo ni un bucle de una negra o más se enteran de que hay swing puesto. El
swing viaja con la sesión, como el tempo.

**Cada pista puede medir lo suyo.** AJUSTAR + SEQ abre el largo de cada pad del
patrón: dieciséis es un compás y cualquier otra cosa es polimetría. Un hat de
siete pasos contra un bombo de dieciséis coinciden en el uno y tardan siete
compases en volver a coincidir, que es lo que hace que un patrón deje de sonar
a bucle. No hubo que reestructurar `Pattern`: **las notas no se mueven, solo se
mueve la vuelta**. El secuenciador lleva una cuenta absoluta desde el PLAY y
cada pista toma su propio resto de ella. Solo se guardan las excepciones, así
que un patrón donde nadie ha tocado esto no ocupa un byte más. Lo que sigue
siendo del compás y no de la pista: el acento, la probabilidad, el
micro-timing y el ratchet — un golpe suena donde suena, pero pega como pega el
compás.

El patrón corre sobre el mismo reloj de semicorcheas que los loops
sincronizados, así que nunca se separa de ellos, y cambiar el tempo no lo corta.

## Las ocho escenas

Una escena es **lo que suena**: qué pads van en bucle y con qué patrón. Es la
regla que Live Loops usa para enseñar la estructura de un tema sin explicarla —
disparas una columna y entra la sección entera— traída al sitio donde esta app
pone todo lo que se toca mientras la música corre: la franja de debajo de la
grilla, que ya se turnan los mandos y el secuenciador.

No fue a la grilla a propósito. El cuadrado ya significa un pad y ya significa
un paso del secuenciador; un tercer significado encima habría sido el tercero.

| Gesto | Qué hace |
|-------|----------|
| Toque en una escena | La lanza |
| Mantener pulsada | Guarda en ella lo que esté sonando ahora |
| AJUSTAR y luego una escena | La vacía (con deshacer detrás) |

Lo importante es **cuándo entra**: una escena se pone en cola en el mismo reloj
de semicorcheas que los bucles y entra en la línea de compás, nunca bajo el
dedo. Se puede pedir a mitad de compás sin romper nada, y mientras espera la
celda se pinta en láser. Un bucle que está en la escena vieja y también en la
nueva **no se toca**: pararlo y volver a arrancarlo abriría un agujero en medio
de un sonido que iba a seguir.

El patrón viaja con la escena solo cuando no manda nadie más. Con la cadena o
la canción puestas, ellas deciden el orden de los patrones y la escena respeta
lo que haya: dos cosas peleando por el mismo compás es peor que una escena que
cede.

Las escenas viven en la sesión, como los patrones: una escena nombra pads de
*esta* sesión y no significa nada al lado de otra.

## Cortar un sonido a los dieciséis pads

Desde la hoja de un sonido, **CORTAR** lo parte en trozos y los reparte por pads
seguidos, en el orden en que suenan. Tres maneras: por **transitorios** —los
golpes que encuentra en la propia onda—, **en 8** o **en 16** partes iguales.
La hoja dibuja los cortes encima de la onda antes de crear nada.

Un corte **no copia audio**. `Sound` ya llevaba recorte no destructivo, así que
los dieciséis trozos son dieciséis sonidos apuntando al mismo fichero con
distintos `trimStartMs`/`trimEndMs`. Partir un WAV de un minuto no ocupa un byte
más en el móvil.

Eso obligó a una regla nueva: **el fichero solo se borra cuando ya no lo usa
nadie**. Antes, borrar un sonido se llevaba su WAV siempre, lo que habría dejado
a sus hermanos apuntando a un fichero inexistente.

Los trozos caen en el primer banco con esos pads libres **seguidos**, buscando
C, D, A y B en ese orden: lo tuyo primero, el kit de fábrica lo último que se
pisa. Si no hay sitio seguido en ninguno, no corta y lo dice.

## Del revés

En la hoja de un sonido, **DEL REVÉS** lo da la vuelta. Es el único control
lento de esa hoja porque es el único que **escribe un fichero**: una marca que
el motor honrase al disparar no valía, porque los dieciséis trozos de un corte
comparten un solo fichero y se habrían dado la vuelta todos a la vez.

Lo caro no es invertir las muestras: es **reflejar el recorte**. Una ventana de
0,2 s a 0,8 s de un sonido de un segundo, leída al revés, vuelve a ser de 0,2 s
a 0,8 s; pero una que acababa en 0,3 s empieza en 0,7 s. Sin eso, invertir un
sonido recortado suena a otro trozo del original. El fichero viejo se borra solo
si ya no lo usa nadie, la misma regla que sigue borrar un sonido.

El botón dice en qué estado está el sonido, no lo que va a hacer: leyendo AL
REVÉS, el audio ya está invertido y tocarlo lo devuelve.

## Un controlador MIDI, sin configurar nada

El icono del piano de arriba lista los controladores: los de USB ya están ahí,
los de Bluetooth se buscan con un botón. Se enciende en fósforo mientras hay uno
conectado, así que es también un indicador y no solo una puerta.

**No hay mapeo que montar.** Las notas a partir del do grave —la 36, el C1 que
comparten Akai, Novation y el M-Vave— tocan los dieciséis pads del banco que
tengas delante, en orden. Enchufar y tocar.

Una nota que llega del cable hace lo mismo que un dedo: suena el pad, entra en
el patrón si el secuenciador está escribiendo, y toca su grado si el teclado
está encendido. La velocidad del golpe llega como fuerza, escalada desde el
suelo y no desde cero: muchos pads baratos mandan siempre 100, y ninguno puede
quedarse a cuatro quintos para siempre. START y STOP mueven el secuenciador.

El reloj MIDI se reconoce y se ignora a propósito: seguir el tempo de otro es
una decisión más grande que esta.

Lo que se puede probar sin cable —el protocolo entero, con sus dos trampas: un
Note On de velocidad cero es un Note Off, y un paquete puede traer varios
mensajes de los que solo el primero lleva cabecera— vive en `domain/midi.dart`
y está cubierto.

### Los mandos se aprenden solos

**Mantén pulsado un mando de la franja, mueve el mando físico, y quedan
casados.** No hay lista de CC que rellenar ni menú que abrir: el gesto pasa
encima del mando que quieres mover, que es donde estabas mirando. Mientras
espera, la fila de arriba lo dice y las solapas desaparecen —cambiar de solapa
ahora sería cambiar de novia—, y el mando aprendido lleva el número del control
escrito dentro del dial.

Se casa con el **parámetro**, nunca con el sitio de la franja. Aprender el
filtro con la percusión delante casa el mando con el bus de percusión para
siempre; si se casara con «el primer mando de lo que haya», elegir otro pad
recablearía el controlador por debajo a mitad de toma. Los parámetros del pad
son la excepción a propósito, y siguen al pad elegido: sesenta y cuatro pads por
cinco parámetros no los mapea nadie a mano.

Un mando mueve una sola cosa y una cosa obedece a un solo mando: aprender rompe
los dos matrimonios anteriores. El movimiento que casa **también mueve** el
parámetro, así que el valor sale ya donde está el mando físico en vez de pedir
un segundo meneo.

El canal se ignora, igual que en las notas: un mando es ese mando grite por
donde grite. El único mando de la franja que no se aprende es el que apunta la
fila FX al maestro o al bus, porque cambia lo que miras y no lo que suena, y un
controlador que cambia la vista es un controlador que hay que mirar.

Lo aprendido vive en `midimap.json`, junto a las sesiones y no dentro de
ninguna: pertenece a la mesa, no a la pieza. La pantalla del controlador lista
lo casado con su número de CC, para comprobarlo y para olvidarlo sin tener que
buscar el mando que lo aprendió.

*Lo que no hace:* no hay recogida suave. Al abrir la app con un mapa guardado, el
primer roce de un mando físico salta al valor de ese mando en vez de esperar a
cruzar el que tenía la app. Es la factura de no tener que mover un mando entero
antes de que responda.

### El cable, en la otra dirección

Un interruptor en la pantalla del controlador, **apagado por defecto**: un reloj
que nadie ha pedido arranca la caja de ritmos de otro en mitad de una toma. Con
él encendido salen 24 pulsos por negra, el play, el stop y una nota por cada pad
que suena. Los pads se reparten como ya se reparten al entrar —nota 36 en
adelante— y **cada banco habla por su canal**, porque sesenta y cuatro pads no
caben en uno sin pisarle el mapa de batería a alguien.

El reloj corre en su propio temporizador y no a ráfagas de seis por
dieciseisavo: seis pulsos de golpe llegan como un bulto y se leen como swing al
otro lado. Las notas se sueltan a los 60 ms, porque un pad es un disparo y no
una tecla, y una nota que se queda puesta deja un sintetizador zumbando al
cerrar la app. Y los LED del controlador siguen a los bucles: un pad que entra
en bucle enciende el suyo y uno que sale lo apaga. Lo que *no* vuelve por el
cable es la posición de los mandos aprendidos — sin recogida suave no
arreglaría nada.

Lo que sale se lee con el mismo analizador que lee lo que entra, y hay un test
que lo comprueba: si no, dos Loopers no podrían sincronizarse entre ellos.

## La rejilla como escala

Elige un pad, abre la solapa **ESCALA** de la franja y enciende **TECLADO**: los
dieciséis pads dejan de ser dieciséis sonidos y pasan a ser dieciséis grados de
una escala, tocando ese sonido a esas alturas. Cada pad dice qué nota es.

La escala está bloqueada, así que **no hay nota falsa posible** — que es la
promesa del README aplicada a la melodía en vez de al ritmo. Seis escalas: las
dos pentatónicas, que no pueden sonar mal; mayor, menor y dórica; y cromática
para cuando la escala estorba. Tónica, escala y octava viajan con la sesión,
como el tempo; qué pad la toca, no.

Al pasarse del último grado sigue una octava más arriba en vez de parar, así que
una pentatónica de cinco grados cubre tres octavas en la grilla. Eso es lo que
hace que suene a solo y no a ejercicio.

Dos reglas que sostienen esto: **tocar una nota no cambia el pad elegido** —si
no, la franja dejaría de apuntar al sonido que está sonando— y **el teclado se
apaga al cambiar de banco**, porque la rejilla es siempre el banco que se ve.

## Acordes y arpegio

Dos mandos más en la solapa Escala, y los dos cuentan **en grados de la escala,
nunca en semitonos**: apilar terceras sobre una menor da un acorde menor y
sobre una mayor da uno mayor, sin que nadie lo decida. Es el mismo truco que la
escala bloqueada, un piso más arriba.

- **Acorde**: sola, tercera, tríada o séptima. Cada tecla del teclado suena a
  tantas notas como diga el mando.
- **Arpegio**: junto, sube, baja, o sube y baja. Reparte esas notas en el
  tiempo — y reparte también **las de un paso del secuenciador**: un paso con
  tres pads deja de ser un acorde y pasa a ser una figura. Sube y baja no
  repite los extremos, así que tres notas son cuatro golpes y no seis, y la
  figura sigue cayendo en el tiempo.

## El pad XY

Solapa **XY** de la franja: filtro a lo ancho, drive a lo alto, con un dedo. Es
la mitad de lo que un móvil hace mejor que un ordenador, y la app no la usaba en
ninguna pantalla. No mueve unos mandos paralelos: mueve **los mismos** que los
diales, sobre lo que la solapa FX tenga apuntado —maestro o bus de familia—,
porque dos mandos para un valor acaban contradiciéndose. Ancho y bajo a
propósito: la altura de la franja es altura de la grilla, y la grilla no
devuelve ni un píxel.

## El sintetizador, con los mandos fuera

`voices.dart` y `dsp.dart` llevaban desde el principio un instrumento completo
—osciladores, envolvente AD, biquad, saturador— con todos sus números clavados
dentro de las veinte voces de fábrica. **SINTETIZAR**, en la biblioteca, es ese
mismo motor con seis mandos: tono, caída, largo, drive, ruido y color, más las
cuatro ondas.

Lo que sale cae en la biblioteca como una grabación más, y desde ese momento
*lo es*: se recorta, se corta a los pads, se invierte y se transpone como
cualquier otra. Los mandos se guardan como **posición** y no como hercios, así
que el dial, el control MIDI y el patch hablan el mismo idioma, y el paso a
unidades reales vive en un solo sitio — exponencial, porque todo lo que el oído
oye en proporciones se recorre así. Cada movimiento suena al instante: un
sintetizador que no se oye al girar un mando es una lista de números.

## Tono real, y estirar al tempo

Todo lo demás en esta app es cinta: subir el tono también acelera. La hoja del
sonido tiene las dos operaciones que rompen esa atadura, y las dos **reescriben
el fichero** —por eso están ahí y no en un mando, que arrastrado lo reescribiría
sesenta veces por segundo—:

- **Tono real**: ±12 semitonos sin cambiar el largo.
- **Estirar**: al tempo de la sesión, sin cambiar el tono. La hoja lee el tempo
  del sonido al abrirse y lo dice.

Debajo hay WSOLA: se corta el sonido en ventanas solapadas y se vuelven a poner
más juntas o más separadas, deslizando cada una hasta donde encaja mejor con lo
que ya está puesto — esa última parte es lo que evita que suene a flanger. El
tono es estirar por el intervalo y luego leerlo más deprisa por el mismo
intervalo: los dos errores se anulan en el tiempo y se suman en el tono.

El tempo se detecta sin una sola FFT: se mide cómo sube la energía —solo las
subidas, porque una nota apagándose no es un evento— y se correlaciona esa curva
consigo misma. **Contesta «no sé» en vez de adivinar** cuando el sonido no llega
a dos golpes: un tempo equivocado es peor que ninguno, porque todo lo que venga
detrás se estira a él.

## Puntos de guardado

La sesión se escribe sola 800 ms después de cada edición, así que sin nada más
no hay forma de volver a un estado que valía la pena. Deshacer camina hacia
atrás paso a paso; un **punto de guardado** es lo otro: «así sonaba antes de
ponerme a cambiarlo todo».

Están en la lista de sesiones, manteniendo pulsada una y eligiendo **Puntos de
guardado**. Ocho por sesión, y el tope es por sesión y no en total, así que
llenar una nunca borra los de otra. Guardar solo se ofrece para la sesión
abierta: el instrumento sostiene una a la vez, y una foto de una sesión que no
estás tocando sería una copia de lo que ya hay en disco.

**Restaurar devuelve el contenido, nunca la identidad.** Vuelven pads, patrones,
tempo, swing y escala; el id, el nombre y la fecha de nacimiento siguen siendo
los de la sesión abierta. Si volviera también la identidad, la lista de sesiones
se quedaría apuntando a un fantasma. Restaurar pasa por deshacer, así que volver
al punto equivocado está a un toque de arreglarse.

Viven en su propio fichero (`savepoints.json`) y no dentro de cada sesión: un
documento de sesión que cargara ocho copias de su propio pasado se reescribiría
entero, y ocho veces más gordo, en cada autoguardado.

## Rescatar lo que acaba de sonar

Mientras el instrumento está en pantalla, la app **siempre tiene guardada la
última media hora de minuto** de la salida del mezclador —treinta segundos, con
los efectos puestos y sin abrir jamás el micrófono—. El botón del reloj de la
barra de arriba se lleva **los últimos cuatro compases** al primer pad libre.

Compases y no segundos: un trozo cortado a la rejilla vuelve a caer en ella a
tiempo.

Sirve para dos cosas a la vez. Pedido justo después de algo bueno es un
**rescate**: ya no hay que decidir *antes* de tocar si merecía la pena grabarlo.
Pedido con varios bucles sonando es un **resampleo**: cuatro capas se quedan en
un solo pad y liberan voces.

**Por qué existe un único grifo.** El motor entrega un solo flujo de la salida
del mezclador: abrir un segundo pararía el primero. Así que exportar la sesión,
resamplear y el rescate no abren cada uno el suyo — todos beben de `MixerTap`,
que es también quien se come la cabecera WAV del principio para que ningún
rescate empiece con un chasquido. Y por eso EXPORTAR ya no usa la cabecera del
motor para cerrar su fichero: esa describe el flujo entero, y una toma puede
empezar mucho después de que el grifo se abriera.

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

### Una pista por familia

Manteniendo pulsado EXPORTAR salen cuatro ficheros, uno por familia. En **cuatro
pasadas y no en cuatro ficheros a la vez**: el motor entrega un solo grifo del
mezclador —de ahí que exportar, resamplear y el rescate lo compartan—, así que
se graban una detrás de otra con las demás familias bajadas. **Cada pasada
empieza en una línea de compás**, porque cuatro ficheros que arrancaran en
cuatro puntos distintos del compás no encajarían en nada. La reverb baja con
ellas: una pista sale seca, que es para lo que sirve una pista.

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
  domain/       Modelos inmutables: Sound, PadConfig, Bank, Session, Pattern,
                Song y Scene
  data/         Almacenamiento local, biblioteca, sesiones, kit de fábrica,
                orden de actuación y espacio libre del dispositivo
  audio/        Síntesis, WAV, motor SoLoud, reloj, micrófono y mezcla,
                estiramiento WSOLA y detección de tempo
  state/        SessionController, Sequencer, el aprendizaje del controlador
                y los destellos de la grilla
  ui/pads/      Grilla, bancos, tempo, franja de mando, barra del secuenciador,
                franja de escenas y hoja de la canción
  ui/sampler/   Samplear con el micrófono y revisar lo capturado
  ui/library/   Biblioteca y editor de sonido
  ui/midi/      Controladores y lo que han aprendido
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
- **Buses de familia:** las cuatro familias —percusión, voz, tono, textura— son
  buses de mezcla de verdad, cada uno con su filtro y su drive. Un pad suena
  por el bus de su familia, así que filtrar la percusión filtra la percusión
  entera de una vez, no sonido a sonido. El clic del metrónomo es la excepción:
  sale en seco, porque no es música.
- **Envío compartido:** hay **una sola** reverb, en su propio bus, y cada
  familia decide cuánto le manda. Como en SoLoud un bus es un padre y no un
  envío, mandar significa disparar el mismo sonido dos veces: seco por su
  familia y otra vez dentro de la reverb, al nivel del envío. Cuatro reverbs
  —una por familia— es justamente lo que este diseño existe para evitar.

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
- Efectos por familia: cada una con su filtro, su drive y su envío a la reverb
  compartida, en la misma solapa FX
- Cadena de patrones de 1 a 16 compases
- Modo canción: cualquier patrón, las veces que quieras, en el orden que
  quieras, en el mismo anillo que la cadena
- Ocho escenas por sesión: guardan lo que suena y entran en la línea de compás
- Controlador MIDI por USB y Bluetooth, sin mapeo que configurar
- MIDI learn: mantener pulsado un mando y mover uno físico los casa, y lo
  aprendido sobrevive a cerrar la app
- Probabilidad, micro-timing y ratchet por paso
- Copiar pads y patrones
- Puntos de guardado: ocho instantáneas con nombre por sesión
- Panorama por pad
- Invertir un sonido, con el recorte reflejado
- Tono real y estiramiento al tempo, con detección de BPM
- Modos de golpe y grupos de corte por pad
- Acordes y arpegio sobre la escala
- Pad XY, compresor y chorus en el maestro
- Sintetizador con mandos: sonidos nuevos desde la biblioteca
- MIDI de salida: reloj, transporte, notas y LED de vuelta
- Exportar una pista por familia
- Longitud distinta por pista dentro de un patrón
- Plantilla de sesión y orden de actuación
- Importar WAV, MP3, FLAC y OGG, a cualquier frecuencia
- Aviso de espacio libre antes de una toma larga
- Dos patrones ya escritos en la sesión que se crea sola
- Destello del golpe en el pad, venga de un dedo, del secuenciador o del cable
- La rejilla como escala: seis escalas, tónica y octava
- Rescatar los últimos cuatro compases del máster a un pad
- Cortar un sonido a los pads: por transitorios, en 8 o en 16
- Deshacer hasta veinte pasos: vaciar pad, cambiar sonido y borrar patrón
- Swing por sesión: recto, suave o tresillo
- Acento por paso, con barra en el pad y deslizador en la barra
- Compás de cuenta atrás antes de escribir el patrón
- Licencias de código abierto desde la lista de sesiones
- Logo e iconos generados por código (`tool/make_icon.py`)

Pendiente:

- Elegir licencia del repositorio
- **Cuarenta y dos pruebas en el móvil**, escritas paso a paso en el capítulo 07
  del artifact «Estado del arte». Es el cuello de botella real del proyecto: se
  ha construido muchísimo más de lo que se ha oído. Sin dedo delante sigue sin
  verificar todo lo de los últimos meses: buses, MIDI learn, escenas, canción,
  reverse, modos de golpe, acordes, XY, sintetizador, tono real, polimetría,
  MIDI de salida y exportación por pistas
- El jitter de 8 ms del reloj (defecto 04). `playClocked` existe en la 4.1.7,
  pero no acepta bucle ni pausa y cuesta unos dos búferes de latencia: hay que
  comprobar con la oreja que el recorte de los sonidos sobrevive al cambio
- Tres funciones del catálogo se quedan fuera por plataforma y no por tiempo:
  **separación de stems** (necesita un modelo entrenado y un tiempo de
  ejecución dentro del APK), **Ableton Link** (hay que envolver a mano la
  librería de C++) y **la app como plugin** (AUv3 no existe fuera de Apple y el
  proyecto AAP de Android sigue sin API estable)

## Fuera de alcance

Colaboración, nube y cuentas, tienda de sonidos, automatización por pistas y
mezclador multipista completo.

*MIDI externo salió de esta lista el 2026-08-21: entra de verdad.*

## Notas de compilación

El proyecto tiene **código de plataforma propio**, corto y en un solo sitio:
`MainActivity.kt` y `AppDelegate.swift` responden al canal `looper/storage` con
el espacio libre del dispositivo. Flutter no trae forma de preguntarlo, y
cuarenta líneas de Kotlin y Swift son más baratas que una dependencia nueva
teniendo las versiones que hay clavadas debajo. Si el canal no contesta, la app
simplemente no avisa.

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
