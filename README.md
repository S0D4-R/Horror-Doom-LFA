# PANDOOMONIUM — Horror Doom LFA

Juego de terror en **primera persona** hecho con **Godot 4.7**. El jugador recorre laberintos oscuros
mientras es perseguido por **Abaddon**, un enemigo controlado por un autómata finito que calcula su
camino con **Dijkstra** sobre un grafo de celdas. El objetivo depende del modo: escapar de la salida
o sobrevivir el mayor tiempo posible.

Pertenece a la materia **Lenguajes Formales y Autómatas (LFA)**: el núcleo del proyecto es la
implementación de un **grafo** (mapas + camino más corto) y una **máquina de estados finita** (IA del enemigo).
La parte visual/3D y de sonido está construida alrededor de esos dos conceptos.

---

## Índice

1. [Cómo ejecutar](#cómo-ejecutar)
2. [Modos de juego](#modos-de-juego)
3. [Controles](#controles)
4. [Estructura del proyecto](#estructura-del-proyecto)
5. [Estructuras de datos](#estructuras-de-datos)
   - [Formato de los mapas](#formato-de-los-mapas)
   - [Construcción 3D de los mapas](#construcción-3d-de-los-mapas)
   - [Grafo y Dijkstra](#grafo-y-dijkstra)
   - [Autómata del enemigo](#autómata-del-enemigo)
   - [Otras estructuras](#otras-estructuras)
6. [Flujo de escenas y arquitectura](#flujo-de-escenas-y-arquitectura)
7. [Sistemas del juego](#sistemas-del-juego)
8. [Multimedia (assets y audio)](#multimedia-assets-y-audio)
9. [Easter eggs](#easter-eggs)
10. [Notas y estado actual](#notas-y-estado-actual)

---

## Cómo ejecutar

1. Instalar **Godot 4.7** (el proyecto usa `config/features = "4.7", "GL Compatibility"`).
2. Abrir la carpeta raíz del repositorio desde el administrador de proyectos de Godot.
3. Ejecutar con **F5**. La escena principal es `Scenes/main_menu_interactive.tscn`
   (`run/main_scene` en `project.godot`).

Configuración relevante de `project.godot`:

| Ajuste | Valor |
|---|---|
| Nombre | `HorrorDoom` |
| Motor de física | `Jolt Physics` |
| Render | `gl_compatibility` (compatible con GPUs modestas) |
| Escena principal | `Scenes/main_menu_interactive.tscn` |

> No hay build de exportación ni dependencias externas: todo el código es **GDScript**.

---

## Modos de juego

Los modos y mapas se definen en `Scenes/partida.gd` (`MODOS` y `MAPAS`).

| Modo | Descripción |
|---|---|
| **U R D4MN3D** | Abaddon te persigue sin descanso. Cuanto más cerca está, más rojo se vuelve el mundo, más fuerte suena tu respiración y más se apaga tu linterna. Debes llegar a la salida. |
| **SUPERVIVENCIA** | No hay salida. Aguanta el mayor tiempo posible con la ayuda de los perks. |
| **Dijkstra** | Modo "extra" definido en el menú (ver [Notas](#notas-y-estado-actual)); comparte comportamiento con Supervivencia. |

Mapas disponibles:

| Mapa | Archivo | Tamaño | Nodos aprox. |
|---|---|---|---|
| Pasillos | `Maps/mapa1_pasillos.txt` | 61 × 37 | 1180 |
| Cementerio | `Maps/mapa2_cementerio.txt` | 40 × 40 | 1195 |
| Plaza | `Maps/mapa3_plaza.txt` | 41 × 41 | 1288 |
| Metro | `Maps/mapa4_metro.txt` | 60 × 40 | 1484 |

---

## Controles

| Acción | Tecla / botón |
|---|---|
| Moverse | `W A S D` / flechas |
| Mirar | Mouse |
| Girar | Flechas izquierda/derecha |
| Correr (consume estamina) | `Shift` |
| Linterna | `1` |
| Pistola | `2` |
| Alternar linterna/pistola | Rueda del mouse |
| Disparar | Clic izquierdo |
| Radar | `R` |
| Pausa | `Esc` |
| Reintentar (en Game Over) | `R` |
| Volver al menú (en Game Over) | `M` |
| Golpe de prueba (debug) | `H` |

En el menú: `W/S` o mouse para elegir, `Enter`/clic para aceptar, `Esc`/clic derecho para volver.

---

## Estructura del proyecto

```
Horror-Doom-LFA/
├── project.godot              # Configuración de Godot
├── icon.svg
├── Maps/                      # Mapas de texto (matrices 0/1)
│   ├── mapa1_pasillos.txt
│   ├── mapa2_cementerio.txt
│   ├── mapa3_plaza.txt
│   └── mapa4_metro.txt
├── Grafo/
│   └── grafo.gd               # Carga de mapas + grafo + Dijkstra (class_name Grafo)
├── Automata/
│   └── enemigo_perseguidor.gd # Autómata finito de Abaddon (class_name EnemigoPerseguidor)
├── Scenes/                    # Lógica del juego y escenas
│   ├── main_menu_interactive.tscn  # Escena principal (menú 3D)
│   ├── main_menu.tscn              # Variante alternativa del menú (Control)
│   ├── map_palace.tscn             # Escena de juego (nodo raíz + mapa_3d.gd)
│   ├── menu.gd                     # Menú principal 3D
│   ├── menu_opcion.gd              # Botón/opción dibujada a mano
│   ├── menu_sigilo.gd              # Pentagrama/círculo ritual y gotas
│   ├── partida.gd                  # Estado compartido: modo, mapa, escenas
│   ├── mapa_3d.gd                  # Construye el mapa 3D, salida, perks, easter eggs
│   ├── jugador.gd                  # Jugador en primera persona (class_name Jugador)
│   ├── enemigo.gd                  # Base de Abaddon: movimiento, ataque, sprite (class_name Abaddon)
│   ├── hud.gd                      # HUD, pausa, game over, efectos (class_name HUD)
│   ├── radar_hud.gd                # Minimapa/radar con ruta Dijkstra (class_name RadarHUD)
│   ├── perk_item.gd                # Ítem flotante recogible (class_name PerkItem)
│   ├── perks.gd                    # Catálogo de perks (class_name Perks)
│   ├── sonidos.gd                  # Sistema de audio (class_name Sonidos)
│   └── Assets/Fonts/               # Fuentes OFL (góticas) + licencias
├── Assets/
│   ├── Chars/                 # Manos, pistola, monstruo (sprites)
│   ├── Icons/                 # Íconos de perks
│   └── MapAssets/             # Texturas por mapa (pared, suelo, techo, lápida)
├── Music/                     # Música y efectos de sonido (.mp3)
└── Automata/, Grafo/, ...     # (los DELETEME.md son marcadores de carpeta)
```

**Dónde está cada cosa (guía rápida):**

| Quiero… | Archivo |
|---|---|
| Entender el grafo y Dijkstra | `Grafo/grafo.gd` |
| Entender la IA del enemigo | `Automata/enemigo_perseguidor.gd` + `Scenes/enemigo.gd` |
| Cambiar mapas/modos | `Scenes/partida.gd` y `Maps/*.txt` |
| Cambiar la generación 3D | `Scenes/mapa_3d.gd` |
| Cambiar controles/física del jugador | `Scenes/jugador.gd` |
| Cambiar HUD, pausa o game over | `Scenes/hud.gd` |
| Cambiar el radar | `Scenes/radar_hud.gd` |
| Cambiar perks | `Scenes/perks.gd` y `Scenes/perk_item.gd` |
| Cambiar sonidos | `Scenes/sonidos.gd` + `Music/` |
| Cambiar el menú | `Scenes/menu.gd`, `menu_opcion.gd`, `menu_sigilo.gd` |

---

## Estructuras de datos

### Formato de los mapas

Los mapas son archivos de texto en `Maps/`. Cada línea que empieza con `#` es cabecera; el resto son
filas de `0` y `1`.

```text
# nombre=Cementerio | tamano=40x40 | formato fila,columna | exterior=1 altura_cielo=20
# jugador=38,38 salida=1,1 enemigo=9,34
1111111111111111111111111111111111111111
1000000000000000000000000000000000000001
...
```

- **Convención:** `0 = piso`, `1 = muro`.
- Una celda es `Vector2i(x = columna, y = fila)`.
- La matriz se indexa como `matriz[y][x]` (fila primero).
- Las cabeceras `jugador`, `salida`, `enemigo`, `fuente` y `tren` se escriben como `fila,columna` y
  se convierten a `Vector2i(columna, fila)`.
- `fuente=fila,columna` construye una fuente 3D en esa celda (Plaza).
- `tren=fila,columna,celdas,orientacion` reserva una huella de 2 celdas de ancho por `celdas` de
  largo y construye un tren de 4 coches; `orientacion` puede ser `h` o `v` (Metro).
- `exterior=1` sustituye el techo interior por un cielo estrellado alto; `altura_cielo` indica su
  altura en metros (Cementerio y Plaza).

`Grafo.cargar(ruta)` (`Grafo/grafo.gd:7`) devuelve un `Dictionary`:

```gdscript
{
    "matriz": Array,            # Array de filas; cada fila es un Array de enteros 0/1
    "jugador": Vector2i,        # posición inicial del jugador
    "salida": Vector2i,         # celda de salida (puede recalcularse)
    "enemigo": Vector2i,        # posición inicial de Abaddon
    "fuente": Vector2i,         # celda de la fuente, o (-1, -1)
    "tren": Vector2i,           # celda inicial de la huella del tren, o (-1, -1)
    "tren_largo": int,          # celdas de largo del tren (0 si no hay)
    "tren_orientacion": String, # "h" o "v"
    "exterior": String,         # "1" si el mapa tiene cielo exterior
    "altura_cielo": String,     # altura del cielo exterior en metros
}
```

### Construcción 3D de los mapas

Los mapas no se generan proceduralmente: son matrices diseñadas a mano en `Maps/*.txt` y
`Scenes/mapa_3d.gd` las convierte en geometría al cargar la escena.

**1. Lectura y preparación.** `Grafo.cargar()` (`Grafo/grafo.gd:7`) lee la cabecera y la matriz;
`_leer_cabecera()` (`Grafo/grafo.gd:39`) convierte `fila,columna` a `Vector2i(columna, fila)` y
guarda `fuente`, `tren`, `exterior` y `altura_cielo`. Después `Mapa3D._ready()`
(`Scenes/mapa_3d.gd:69`) toma esos datos, elige la salida estratégica (salvo que
`respetar_salida_txt` sea `true`) y construye el mapa.

**2. De celda a mundo.** Cada celda mide `tam_celda = 2.0` metros y los muros miden
`alto_muro = 3.0` metros. El centro de una celda `(x, y)` se calcula con
`celda_a_mundo()` (`Scenes/mapa_3d.gd:216`):

```text
mundo = ((x + 0.5) * 2.0, 0.0, (y + 0.5) * 2.0)
```

**3. Muros.** `_construir_muros()` (`Scenes/mapa_3d.gd:318`) recorre la matriz por filas y agrupa
las celdas `1` contiguas en un solo `StaticBody3D` con una `BoxMesh` por tramo. Solo construye
muros "visibles": aquellos que tienen al menos una celda de piso en su vecindad de 8 celdas
(`_es_visible()`, `Scenes/mapa_3d.gd:235`). Los `1` rodeados completamente por otros `1` se omiten
para no generar geometría interior inútil. Las celdas especiales (`fuente` y `tren`) se saltan
porque se construyen aparte.

**4. Suelo y techo.** `_construir_suelo_y_techo()` (`Scenes/mapa_3d.gd:593`) crea una caja de suelo
de 0.2 m de grosor con colisión. En interiores coloca un techo bajo a `alto_muro + 0.1`; en mapas
con `exterior=1` coloca un cielo a `altura_cielo` metros, sin colisión, con un material unshaded,
sin niebla y una textura de 48 m por defecto para que las estrellas no se repitan demasiado. Ese
cielo se extiende 4 veces el tamaño del mapa para cubrir el horizonte.

**5. Texturas.** `_preparar_materiales()` (`Scenes/mapa_3d.gd:250`) busca las texturas en
`Assets/MapAssets/<NombreDelMapa>/`, donde `<NombreDelMapa>` sale del archivo después del primer
`_` y con la primera letra en mayúscula (`mapa4_metro.txt` → `Metro/`). Para `pared`, `suelo`,
`techo` y `lapida` carga `<nombre>_albedo.png`, `<nombre>_normal.png` y, si existe,
`<nombre>_roughness.png`. Usa mapeo triplanar en coordenadas de mundo con una repetición de 2 m;
si falta una textura, cae en un color plano.

**6. Elementos especiales.**

- **Cementerio:** los `1` aislados (sin ningún otro `1` en sus 8 vecinos y fuera del borde) se
  convierten en lápidas con parcela, tierra, cabeza, cruz opcional y colisión
  (`_crear_lapida()`, `Scenes/mapa_3d.gd:379`). En la matriz siguen siendo muro para el grafo y
  la persecución, pero visualmente son tumbas. `mapa2_cementerio.txt` tiene 95.
- **Plaza:** la cabecera `fuente=fila,columna` marca una celda `1` que no se dibuja como muro; en
  su lugar `_construir_fuente()` (`Scenes/mapa_3d.gd:445`) crea una fuente con base de piedra,
  agua, pedestal, recipiente superior, remate y colisión cilíndrica. En `mapa3_plaza.txt` está en
  `fila 20, columna 20`.
- **Metro:** la cabecera `tren=fila,columna,celdas,orientacion` reserva una huella de 2 celdas de
  ancho por `celdas` de largo. Esas celdas son `1` en la matriz, pero `_construir_tren()`
  (`Scenes/mapa_3d.gd:485`) las salta y construye balasto, durmientes, rieles, cuatro coches con
  ventanas iluminadas, franja amarilla y colisión. `orientacion` puede ser `h` o `v`. En
  `mapa4_metro.txt`: `tren=18,14,32,h`.

**7. Mapas actuales.**

| Mapa | Construcción |
|---|---|
| Pasillos | 61 × 37. Laberinto de pasillos y muros; 1180 nodos de piso. |
| Cementerio | 40 × 40. Terreno abierto con 95 bloques aislados convertidos en lápidas y cielo estrellado a 20 m. |
| Plaza | 41 × 41. Cuatro edificios en las esquinas con patios interiores y puertas de dos celdas de profundidad, plaza central abierta con fuente y bloques decorativos; cielo a 16 m. 1288 nodos. |
| Metro | 60 × 40. Anillo de servicio de 4 celdas de ancho, sala central con 24 columnas, pasillos de conexión de 2 celdas de ancho y tren de 4 coches en el centro. 1484 nodos. |

**8. Para añadir un mapa nuevo.** Crea el `.txt` con su cabecera y matriz (borde cerrado con `1`,
celdas `0` conectadas y celdas especiales en `1`), añade la entrada en `Scenes/partida.gd` y, si
quieres texturas propias, crea `Assets/MapAssets/<Nombre>/` con los PNG correspondientes.

### Grafo y Dijkstra

Implementado en `Grafo/grafo.gd`:

- **Nodos:** cada celda de piso (`0`) es un nodo.
- **Aristas:** conexiones en 4 direcciones entre celdas de piso (`Grafo.vecinos()`).
- **Peso:** cada arista cuesta `1` (grafo no ponderado; Dijkstra se reduce a BFS con cola de prioridad).
- **Búsqueda:** `Grafo.dijkstra(matriz, inicio, meta)` devuelve `Array[Vector2i]` con la ruta completa
  (incluye inicio y meta) o un arreglo vacío si no hay camino.
- **Cola de prioridad:** min-heap binario implementado a mano (`_heap_meter`, `_heap_sacar`) sobre un
  `Array` de pares `[distancia, celda]`.
- **Estructuras auxiliares:** dos `Dictionary`:
  - `dist[celda] = distancia mínima`
  - `previo[celda] = celda anterior` (para reconstruir la ruta)

La misma función se reutiliza en tres lugares:
- Persecución de Abaddon (`Scenes/enemigo.gd:159`).
- Movimiento del autómata (`Automata/enemigo_perseguidor.gd:78`).
- Ruta a la salida dibujada en el radar (`Scenes/radar_hud.gd:78`).

`Scenes/mapa_3d.gd` incluye además `_dijkstra_distancias()` para calcular, desde el jugador y desde el
enemigo, la distancia a todas las celdas; con eso elige una **salida estratégica** (lejos, accesible y en
un corredor de baja conectividad).

### Autómata del enemigo

`Automata/enemigo_perseguidor.gd` define una **máquina de estados finita (Mealy)** que hereda de
`Abaddon` (`Scenes/enemigo.gd`):

```text
Q  = { IDLE, ESPERANDO, PERSIGUIENDO, ATURDIDO, CONGELADO }
Σ  = { JUGADOR_CERCA, JUGADOR_LEJOS, DISPARO, RECUPERADO, CONGELAR, DESCONGELAR }
q0 = IDLE
δ  = tabla TRANSICIONES (estado, evento) -> estado
```

Detalles:

- La tabla de transición es un `Dictionary` constante `TRANSICIONES`
  (`Automata/enemigo_perseguidor.gd:27`). Si el par `(estado, evento)` no existe, el estado no cambia.
- `JUGADOR_CERCA` **no** está en la tabla porque tiene una guarda: solo pasa a `PERSIGUIENDO` cada
  `pasos_por_movimiento` pasos del jugador (o de inmediato si `persecucion_continua = true`).
- La distancia "cerca/lejos" se mide en **nodos del grafo** (longitud de la ruta Dijkstra), no en línea
  recta; así una pared entre ambos cuenta como distancia.
- La salida (acción) al entrar en `PERSIGUIENDO` es avanzar una celda siguiendo la ruta calculada.
- `_recalcular_ruta()` y `_seguir_ruta()` se heredan de `Abaddon` y se sobrescriben según el modo.
- La señal `estado_cambiado(anterior, nuevo)` permite observar las transiciones.

### Otras estructuras

| Estructura | Dónde | Uso |
|---|---|---|
| `Array[Vector2i]` (ruta) | `enemigo.gd`, `radar_hud.gd` | Camino devuelto por Dijkstra |
| `Dictionary` de perks | `mapa_3d.gd` (`_perks_en_mapa`, `posiciones_perks`) | Tipo de perk → nodo / celda |
| `Array` de mapas/modos | `partida.gd` (`MAPAS`, `MODOS`) | Catálogo de opciones del menú |
| `Dictionary` de sonidos | `sonidos.gd` (`ARCHIVOS`) | Evento lógico → archivo en `Music/` |
| Buffer de entrada | `mapa_3d.gd` (`_ee_buffer`) | Detección de códigos Konami/lluvia |
| `Dictionary` de distancias | `grafo.gd`, `mapa_3d.gd` | Resultado de Dijkstra y elección de salida |

---

## Flujo de escenas y arquitectura

```text
main_menu_interactive.tscn (menu.gd)
        │  COMENZAR
        ▼
map_palace.tscn (mapa_3d.gd)
        │  crea en tiempo de ejecución:
        │    ├── muros / suelo / techo
        │    ├── Jugador (jugador.gd)
        │    ├── EnemigoPerseguidor (enemigo_perseguidor.gd → enemigo.gd)
        │    ├── PerkItem ×3 (perk_item.gd)
        │    └── HUD (hud.gd) + RadarHUD (radar_hud.gd)
        │
        ├── victoria → HUD → menú
        └── muerte   → HUD Game Over → R reintenta / M menú
```

- `Partida` (`Scenes/partida.gd`) guarda el modo y el mapa elegidos en **variables estáticas**, por lo que
  sobreviven al cambio de escena sin necesidad de un autoload.
- Casi todos los nodos visuales se **crean por código** en `_ready()`; las escenas `.tscn` son mínimas
  (un nodo raíz con su script). Esto facilita leer la lógica sin inspeccionar el editor.
- Señales clave del jugador: `celda_cambiada`, `perk_recogido`, `arma_cambiada`, `disparo_realizado`,
  `escudo_roto`, `ventana_huida_iniciada/terminada`, `jugador_muerto`.
- `mapa_3d.gd` conecta `celda_cambiada` con el autómata (`registrar_movimiento_jugador`) y con la
  detección de llegada a la salida.

---

## Sistemas del juego

### Jugador (`Scenes/jugador.gd`)
Primera persona con cámara, linterna (`SpotLight3D`) y colisión de cápsula.
- **Estamina:** `STAMINA_MAX = 5 s`; correr consume y caminar recarga.
- **Armas:** linterna y pistola; la pistola solo se obtiene con el perk correspondiente.
- **Persecución:** la cercanía al enemigo controla el volumen de respiración/susurros, el tinte rojo y el
  apagado automático de la linterna (con histéresis).
- **Escudo:** absorbe un golpe y abre una "ventana de huida" de 10 s (con reloj sonando).
- **Muerte:** la cámara cae al suelo y el HUD muestra Game Over.

### Abaddon (`Scenes/enemigo.gd`)
`CharacterBody3D` que persigue al jugador usando Dijkstra.
- Velocidad de persecución `4.8 m/s`: supera al jugador caminando (`4.2`) pero no corriendo (`7.0`).
- Al recibir un disparo queda **aturdido** entre 2 y 4 s.
- Se puede **congelar/descongelar** (usado por la ventana de huida y los easter eggs).
- Sprite 2D tipo billboard (`Assets/Chars/monster.png`); si falta, usa una cápsula provisional.

### HUD (`Scenes/hud.gd`)
Construido por código: manos con arma, mira, munición, íconos de radar/escudo, barra de estamina,
mensajes, pantalla de Game Over/Victoria, menú de pausa (`Esc`) y efectos de pantalla
(shader rojo de cercanía, inversión de colores durante la huida, pentagrama).

### Radar (`Scenes/radar_hud.gd`)
Minimapa circular que dibuja los muros cercanos, la ruta Dijkstra hacia la salida, el enemigo y la salida.
Cada 3 giros del escáner muestra una flecha hacia el perk más cercano. Dura `7 s`.

### Perks (`Scenes/perks.gd`, `Scenes/perk_item.gd`)
Tres tipos: **pistola**, **radar** y **escudo**. Flotan, brillan y se recogen al tocarlos. Cuando se
recogen todos, el mapa los regenera uno a uno cada 20 s (`INTERVALO_REGENERACION`).

### Audio (`Scenes/sonidos.gd`)
Sistema centralizado: cada evento lógico se mapea a un nombre de archivo en `Music/`. Busca `.ogg`,
`.wav` o `.mp3` y cachea los recursos. Soporta reproducción única y bucles. Si falta un archivo, avisa una
sola vez por consola y no suena.

### Menú (`Scenes/menu.gd`, `menu_opcion.gd`, `menu_sigilo.gd`)
Menú 3D con el mapa del cementerio como escenario, cámara que viaja entre "planos", tipografía gótica,
tinte rojo, ceniza, luces defectuosas, pentagrama y gotas de sangre. Las opciones se dibujan a mano
(sin cajas) y reaccionan al mouse/teclado.

---

## Multimedia (assets y audio)

- **Personajes/UI:** `Assets/Chars/` (manos, pistola, monstruo, etc.) y `Assets/Icons/` (perks).
- **Fuentes:** `Scenes/Assets/Fonts/` (UnifrakturCook, PirataOne, Cinzel) con licencias OFL incluidas.
- **Música/SFX:** `Music/`. El mapeo evento → archivo está en `Scenes/sonidos.gd` (`ARCHIVOS`):

| Evento | Archivo |
|---|---|
| Pasos al caminar | `steps.mp3` |
| Pasos al correr | `Running footsteps [QnJ26_ZlEbo].mp3` |
| Recoger ítem | `pickupitem.mp3` |
| Linterna | `Flashlight Sound Effect sfx [-38q978nFnc].mp3` |
| Disparo | `shot.mp3` |
| Respiración cercana | `heavy breathing sound effect [54Pqc-Abgas].mp3` |
| Susurros | `whispers.mp3` |
| Reloj (huida) | `ticking.mp3` |
| Menú | `select.mp3`, `accept.mp3` |
| Música de mapa | `mapa1_pasillos.mp3`, `mapa2_cementerio.mp3`, `mapa3_plaza.mp3` |

Los archivos `.import` son metadatos generados por Godot y no deben editarse a mano.

---

## Easter eggs

Definidos en `Scenes/mapa_3d.gd`:

- **Konami:** `↑ ↑ ↓ ↓ ← → ← → clic-izq clic-der` → teletransporta al jugador a la salida.
- **Lluvia:** `← → clic-der clic-der` → hace aparecer junto al jugador todos los perks que falten.

Las entradas se acumulan en un buffer de 10 caracteres y se comparan por sufijo.

---

## Notas y estado actual

- **Motor:** Godot 4.7, GDScript, renderer GL Compatibility. No hay tests automatizados.
- **Menú:** `menu.gd` busca las fuentes en `res://Assets/Fonts/`, pero los archivos están en
  `res://Scenes/Assets/Fonts/`; si no se encuentran, usa fuentes del sistema. Es un ajuste pendiente
  (mover la carpeta o corregir la ruta).
- **Modo Dijkstra:** aparece en `Partida.MODOS` (índice 2) pero el enum `Partida.Modo` solo define
  `U_R_D4MN3D` y `SUPERVIVENCIA`. Al elegirlo se comporta como Supervivencia (sin salida estratégica ni
  efectos de cercanía). Pendiente de implementar o retirar del menú.
- **Audio faltante:** `escudo_roto` no tiene archivo en `Music/`; el sistema lo avisa y continúa sin sonido.
- **Assets provisionales:** hay sprites alternativos (`mano_linterna.png`, `mano_pistola.png`, etc.) que
  no se usan actualmente; el HUD usa las versiones `*_recolor`.
- **Rendimiento:** los mapas se construyen por código creando un `StaticBody3D` por bloque de muro; los
  mapas grandes pueden generar muchos nodos. El renderer es GL Compatibility para amplia compatibilidad.

---

## Créditos

- Proyecto académico de **Lenguajes Formales y Autómatas**.
- Repositorio: <https://github.com/S0D4-R/Horror-Doom-LFA>
- Fuentes bajo licencia **SIL Open Font License** (ver `Scenes/Assets/Fonts/LICENCIAS.txt`).
- Efectos de sonido y música de uso libre provenientes de distintas fuentes públicas (ver nombres de
  archivo en `Music/`).
