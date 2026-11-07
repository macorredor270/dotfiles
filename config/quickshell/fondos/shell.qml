import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Selector de fondos · se abre con «fondo» (Ctrl+Alt+W).
// Toda la lógica (carpetas, guardar, bloqueo) está en ~/.local/bin/fondo; esto solo es la vista.
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string fondo: home + "/.local/bin/fondo"

    // paleta: la misma de la waybar y hyprlock
    readonly property color cTarjeta: "#f2121212"
    readonly property color cBorde:   "#17ffffff"
    readonly property color cTexto:   "#e6e6e6"
    readonly property color cTenue:   "#6e6e6e"
    readonly property color cSuave:   "#9a9a9a"
    readonly property string fSerif:  "DM Serif Display"
    readonly property string fUi:     "Inter Display"
    readonly property string fMono:   "JetBrainsMono Nerd Font"

    property var todas: []          // todas las rutas, más nuevas primero
    property var carpetas: []
    property string carpetaSel: ""  // "" = todas
    property string actual: ""
    property string actualInicial: ""
    property string modo: "rellenar"
    property string modoInicial: "rellenar"
    property bool subcarpetas: false
    property bool probado: false
    property bool cargando: true
    property string aviso: ""

    ListModel { id: modelo }

    // ── procesos ───────────────────────────────────────────────────────────
    Component {
        id: tarea
        Process {
            id: p
            property var alTerminar: null
            property bool salidaLista: false
            property bool terminado: false
            stdout: StdioCollector {
                onStreamFinished: {
                    if (p.alTerminar) p.alTerminar(text)
                    p.salidaLista = true
                    if (p.terminado) p.destroy()
                }
            }
            onExited: { p.terminado = true; if (p.salidaLista) p.destroy() }
        }
    }
    function ejecutar(args, cb) {
        const p = tarea.createObject(root, { command: [root.fondo].concat(args), alTerminar: cb || null })
        p.running = true
    }

    function cargarEstado(cb) {
        ejecutar(["estado"], function (txt) {
            const cs = []
            for (const l of txt.split("\n")) {
                const i = l.indexOf("="); if (i < 0) continue
                const k = l.slice(0, i), v = l.slice(i + 1)
                if (k === "actual") root.actual = v
                else if (k === "modo") root.modo = v
                else if (k === "subcarpetas") root.subcarpetas = (v === "si")
                else if (k === "carpeta") cs.push(v)
            }
            root.carpetas = cs
            if (root.carpetaSel !== "" && cs.indexOf(root.carpetaSel) < 0) root.carpetaSel = ""
            if (cb) cb()
        })
    }
    function cargarLista() {
        root.cargando = true
        ejecutar(["lista"], function (txt) {
            root.todas = txt.split("\n").filter(l => l.length > 0)
            root.cargando = false
            filtrar(true)
        })
    }
    function recargar() { cargarEstado(cargarLista) }

    Component.onCompleted: cargarEstado(function () {
        root.actualInicial = root.actual
        root.modoInicial = root.modo
        cargarLista()
    })

    function carpetaDe(ruta) {
        let mejor = ""
        for (const c of root.carpetas)
            if (ruta.startsWith(c + "/") && c.length > mejor.length) mejor = c
        return mejor
    }
    function nombre(ruta) { return ruta.split("/").pop() }
    function corta(ruta) { return ruta.startsWith(root.home) ? "~" + ruta.slice(root.home.length) : ruta }

    function filtrar(irAlActual) {
        const q = busqueda.text.toLowerCase()
        const anterior = grid.currentIndex >= 0 && grid.currentIndex < modelo.count ? modelo.get(grid.currentIndex).ruta : ""
        modelo.clear()
        for (const r of root.todas) {
            if (root.carpetaSel !== "" && carpetaDe(r) !== root.carpetaSel) continue
            if (q !== "" && nombre(r).toLowerCase().indexOf(q) < 0) continue
            modelo.append({ ruta: r })
        }
        const objetivo = irAlActual ? root.actual : anterior
        let idx = 0
        for (let i = 0; i < modelo.count; i++) if (modelo.get(i).ruta === objetivo) { idx = i; break }
        grid.currentIndex = modelo.count ? idx : -1
        grid.positionViewAtIndex(Math.max(idx, 0), GridView.Contain)
    }

    function seleccionada() {
        return grid.currentIndex >= 0 && grid.currentIndex < modelo.count ? modelo.get(grid.currentIndex).ruta : ""
    }
    function avisar(t) { root.aviso = t; avisoTimer.restart() }
    Timer { id: avisoTimer; interval: 2200; onTriggered: root.aviso = "" }

    // ── acciones ───────────────────────────────────────────────────────────
    function poner(ruta) {
        if (!ruta) return
        ventana.visible = false
        root.probado = false
        ejecutar(["poner", ruta, root.modo], function () { Qt.quit() })
    }
    function probar(ruta) {
        if (!ruta) return
        root.probado = true
        ejecutar(["probar", ruta, root.modo])
        avisar("probando · enter para quedártelo, esc para volver")
    }
    function cerrar() {
        if (root.probado && root.actualInicial !== "") {
            ventana.visible = false
            ejecutar(["probar", root.actualInicial, root.modoInicial], function () { Qt.quit() })
        } else Qt.quit()
    }
    function cambiarModo() {
        const modos = ["rellenar", "ajustar", "centrar"]
        root.modo = modos[(modos.indexOf(root.modo) + 1) % modos.length]
        if (root.probado && seleccionada()) ejecutar(["probar", seleccionada(), root.modo])
    }
    function aleatorio() {
        if (!modelo.count) return
        grid.currentIndex = Math.floor(Math.random() * modelo.count)
        probar(seleccionada())
    }
    function bloqueo() {
        const r = seleccionada(); if (!r) return
        ejecutar(["bloqueo", r], function () { avisar("fondo del bloqueo cambiado") })
    }
    function alternarSub() {
        root.subcarpetas = !root.subcarpetas
        ejecutar(["subcarpetas", root.subcarpetas ? "si" : "no"], function () { cargarLista() })
    }
    function quitarCarpeta(c) {
        ejecutar(["carpetas", "quitar", c], function () { avisar("carpeta quitada: " + corta(c)); recargar() })
    }
    function anadirRuta(t) {
        t = t.trim(); if (!t) return
        ejecutar(["carpetas", "añadir", t], function (salida) {
            const d = salida.trim()
            if (!d) { avisar("esa carpeta no existe"); return }
            entradaRuta.text = ""; nuevaCarpeta.abierta = false
            enfocarGrid()
            root.carpetaSel = d
            avisar("carpeta añadida: " + corta(d))
            recargar()
        })
    }
    function examinar() {
        ventana.visible = false   // el diálogo quedaría debajo de esta capa
        ejecutar(["carpetas", "elegir"], function (salida) {
            ventana.visible = true
            const d = salida.trim()
            nuevaCarpeta.abierta = false
            if (d) { root.carpetaSel = d; avisar("carpeta añadida: " + corta(d)); recargar() }
            enfocarGrid()
        })
    }
    function cambiarCarpeta(paso) {
        const lista = [""].concat(root.carpetas)
        root.carpetaSel = lista[(lista.indexOf(root.carpetaSel) + paso + lista.length) % lista.length]
        filtrar(false)
    }
    function enfocarGrid() { grid.forceActiveFocus() }

    // ── ventana ────────────────────────────────────────────────────────────
    PanelWindow {
        id: ventana
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fondos"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Item {
            id: lienzo
            anchors.fill: parent

            Rectangle {
                anchors.fill: parent
                color: "#99000000"
                MouseArea { anchors.fill: parent; onClicked: root.cerrar() }
            }

            Rectangle {
                id: tarjeta
                anchors.centerIn: parent
                readonly property int cols: Math.max(2, Math.min(4, Math.floor((lienzo.width * 0.86 - 56) / 300)))
                width: cols * grid.cellWidth + 56
                readonly property int filas: Math.max(2, Math.min(3, Math.ceil(modelo.count / cols)))
                height: Math.min(lienzo.height * 0.84, filas * grid.cellHeight + 172)
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                radius: 14
                color: root.cTarjeta
                border.color: root.cBorde
                border.width: 1
                opacity: 0
                scale: 0.985
                Component.onCompleted: { opacity = 1; scale = 1 }
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                MouseArea { anchors.fill: parent; onClicked: root.enfocarGrid() }

                // ── cabecera ──
                Text {
                    id: titulo
                    x: 28; y: 18
                    text: "Fondos"
                    color: root.cTexto
                    font.family: root.fSerif
                    font.pixelSize: 34
                }
                Text {
                    anchors { left: titulo.right; leftMargin: 14; baseline: titulo.baseline }
                    text: root.cargando ? "buscando…" : modelo.count + (modelo.count === 1 ? " imagen" : " imágenes")
                    color: root.cTenue
                    font.family: root.fUi; font.pixelSize: 13
                }

                Row {
                    anchors { right: parent.right; rightMargin: 28; verticalCenter: titulo.verticalCenter }
                    spacing: 18
                    Opcion { texto: root.modo; pista: "m"; onPulsado: root.cambiarModo() }
                    Opcion { texto: "subcarpetas"; activa: root.subcarpetas; pista: "s"; onPulsado: root.alternarSub() }
                }

                // ── carpetas ──
                Flickable {
                    id: filaCarpetas
                    anchors { left: parent.left; leftMargin: 22; right: cajaBusqueda.left; rightMargin: 16 }
                    y: 72; height: 30
                    contentWidth: chips.width; clip: true
                    flickableDirection: Flickable.HorizontalFlick
                    Row {
                        id: chips
                        spacing: 4
                        Chip { texto: "todas"; activa: root.carpetaSel === ""; onPulsado: { root.carpetaSel = ""; root.filtrar(false) } }
                        Repeater {
                            model: root.carpetas
                            Chip {
                                required property string modelData
                                texto: root.nombre(modelData) || "/"
                                ruta: modelData
                                quitable: true
                                activa: root.carpetaSel === modelData
                                onPulsado: { root.carpetaSel = modelData; root.filtrar(false) }
                                onQuitar: root.quitarCarpeta(modelData)
                            }
                        }
                        Item {
                            id: nuevaCarpeta
                            property bool abierta: false
                            height: 30
                            width: abierta ? cajaRuta.width : masTxt.implicitWidth + 24
                            Text {
                                id: masTxt
                                visible: !nuevaCarpeta.abierta
                                anchors.centerIn: parent
                                text: "+ carpeta"
                                color: masArea.containsMouse ? root.cTexto : root.cTenue
                                font.family: root.fUi; font.pixelSize: 13
                                MouseArea {
                                    id: masArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { nuevaCarpeta.abierta = true; entradaRuta.forceActiveFocus() }
                                }
                            }
                            Rectangle {
                                id: cajaRuta
                                visible: nuevaCarpeta.abierta
                                width: 380; height: 30; radius: 8
                                color: "#0affffff"; border.color: root.cBorde
                                TextInput {
                                    id: entradaRuta
                                    anchors { left: parent.left; leftMargin: 12; right: examinarTxt.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                    color: root.cTexto; selectionColor: "#44ffffff"
                                    font.family: root.fMono; font.pixelSize: 12
                                    clip: true
                                    Text {
                                        visible: !entradaRuta.text
                                        text: "~/ruta/de/la/carpeta"
                                        color: root.cTenue; font: entradaRuta.font
                                    }
                                    Keys.onReturnPressed: root.anadirRuta(text)
                                    Keys.onEnterPressed: root.anadirRuta(text)
                                    Keys.onEscapePressed: { text = ""; nuevaCarpeta.abierta = false; root.enfocarGrid() }
                                }
                                Text {
                                    id: examinarTxt
                                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                    text: "examinar"
                                    color: exArea.containsMouse ? root.cTexto : root.cSuave
                                    font.family: root.fUi; font.pixelSize: 12
                                    MouseArea { id: exArea; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.examinar() }
                                }
                            }
                        }
                    }
                }

                // ── búsqueda ──
                Rectangle {
                    id: cajaBusqueda
                    anchors { right: parent.right; rightMargin: 28 }
                    y: 72; width: 200; height: 30; radius: 8
                    color: busqueda.activeFocus ? "#0affffff" : "transparent"
                    border.color: busqueda.activeFocus || busqueda.text ? root.cBorde : "transparent"
                    TextInput {
                        id: busqueda
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.cTexto; selectionColor: "#44ffffff"
                        font.family: root.fUi; font.pixelSize: 13
                        clip: true
                        onTextChanged: root.filtrar(false)
                        Text {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            visible: !busqueda.text
                            text: busqueda.activeFocus ? "nombre…" : "/ buscar"
                            color: root.cTenue; font: busqueda.font
                        }
                        Keys.onEscapePressed: { if (text) text = ""; else root.enfocarGrid() }
                        Keys.onReturnPressed: root.enfocarGrid()
                        Keys.onEnterPressed: root.enfocarGrid()
                        Keys.onDownPressed: root.enfocarGrid()
                    }
                }

                // ── miniaturas ──
                GridView {
                    id: grid
                    anchors { fill: parent; topMargin: 116; leftMargin: 28; rightMargin: 28; bottomMargin: 52 }
                    cellWidth: 300
                    cellHeight: Math.round(cellWidth * 9 / 16) + 12
                    model: modelo
                    clip: true
                    focus: true
                    keyNavigationEnabled: true
                    keyNavigationWraps: false
                    highlightMoveDuration: 0
                    boundsBehavior: Flickable.StopAtBounds
                    Component.onCompleted: forceActiveFocus()

                    Keys.onPressed: event => {
                        const k = event.key, t = event.text
                        if (k === Qt.Key_Return || k === Qt.Key_Enter) root.poner(root.seleccionada())
                        else if (k === Qt.Key_Space) root.probar(root.seleccionada())
                        else if (k === Qt.Key_Escape) root.cerrar()
                        else if (k === Qt.Key_Tab) root.cambiarCarpeta(1)
                        else if (k === Qt.Key_Backtab) root.cambiarCarpeta(-1)
                        else if (t === "/") busqueda.forceActiveFocus()
                        else if (t === "m") root.cambiarModo()
                        else if (t === "r") root.aleatorio()
                        else if (t === "b") root.bloqueo()
                        else if (t === "s") root.alternarSub()
                        else if (t === "a") { nuevaCarpeta.abierta = true; entradaRuta.forceActiveFocus() }
                        else if (t === "?") ayuda.visible = !ayuda.visible
                        else if (t === "h") moveCurrentIndexLeft()
                        else if (t === "l") moveCurrentIndexRight()
                        else if (t === "k") moveCurrentIndexUp()
                        else if (t === "j") moveCurrentIndexDown()
                        else return
                        event.accepted = true
                    }

                    delegate: Item {
                        id: celda
                        required property int index
                        required property string ruta
                        readonly property bool sel: GridView.isCurrentItem
                        readonly property bool esActual: ruta === root.actual
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Rectangle {
                            id: marco
                            anchors { fill: parent; margins: 6 }
                            radius: 10
                            color: "#0d0d0d"
                            border.width: celda.sel ? 2 : 1
                            border.color: celda.sel ? "#e6ffffff" : "#0fffffff"
                            clip: true

                            Image {
                                id: mini
                                anchors { fill: parent; margins: celda.sel ? 3 : 1 }
                                source: "file://" + celda.ruta
                                sourceSize.width: 560
                                sourceSize.height: 316
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                opacity: status === Image.Ready ? (celda.sel || zona.containsMouse ? 1 : 0.82) : 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                            }
                            // nombre: solo en la seleccionada
                            Rectangle {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 3 }
                                height: 26
                                visible: celda.sel
                                gradient: Gradient {
                                    GradientStop { position: 0; color: "#00000000" }
                                    GradientStop { position: 1; color: "#cc000000" }
                                }
                                Text {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    verticalAlignment: Text.AlignVCenter
                                    text: root.nombre(celda.ruta)
                                    color: root.cTexto
                                    font.family: root.fUi; font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                        // punto blanco: el fondo puesto ahora
                        Rectangle {
                            visible: celda.esActual
                            anchors { top: marco.top; right: marco.right; margins: 10 }
                            width: 8; height: 8; radius: 4
                            color: "#ffffff"
                            border.color: "#66000000"; border.width: 1
                        }
                        MouseArea {
                            id: zona
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onPositionChanged: grid.currentIndex = celda.index
                            onClicked: m => {
                                grid.currentIndex = celda.index
                                root.enfocarGrid()
                                if (m.button === Qt.RightButton) root.probar(celda.ruta)
                                else if (m.button === Qt.MiddleButton) root.bloqueo()
                                else root.poner(celda.ruta)
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: grid
                    visible: !root.cargando && modelo.count === 0
                    horizontalAlignment: Text.AlignHCenter
                    text: busqueda.text ? "Nada se llama así."
                        : root.carpetas.length ? "No hay imágenes aquí.\nAñade otra carpeta con «+ carpeta»."
                        : "Añade una carpeta con «+ carpeta»."
                    color: root.cTenue
                    font.family: root.fUi; font.pixelSize: 14
                    lineHeight: 1.3
                }

                // ── pie: ruta de la seleccionada · avisos ──
                Text {
                    anchors { left: parent.left; leftMargin: 28; right: pieDer.left; rightMargin: 20; bottom: parent.bottom; bottomMargin: 18 }
                    text: root.aviso || root.corta(root.seleccionada())
                    color: root.aviso ? root.cTexto : root.cTenue
                    font.family: root.aviso ? root.fUi : root.fMono
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
                Text {
                    id: pieDer
                    anchors { right: parent.right; rightMargin: 28; bottom: parent.bottom; bottomMargin: 18 }
                    text: "?"
                    color: ayudaArea.containsMouse || ayuda.visible ? root.cTexto : root.cTenue
                    font.family: root.fUi; font.pixelSize: 13; font.weight: Font.Medium
                    MouseArea { id: ayudaArea; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ayuda.visible = !ayuda.visible }
                }

                // ── atajos (con «?») ──
                Rectangle {
                    id: ayuda
                    visible: false
                    anchors { right: parent.right; rightMargin: 20; bottom: parent.bottom; bottomMargin: 44 }
                    width: tabla.width + 40; height: tabla.height + 32
                    radius: 10
                    color: "#fa161616"; border.color: root.cBorde
                    MouseArea { anchors.fill: parent }
                    Grid {
                        id: tabla
                        anchors.centerIn: parent
                        columns: 2; columnSpacing: 22; rowSpacing: 7
                        Repeater {
                            model: [
                                "enter · clic", "poner",
                                "espacio · clic derecho", "probar sin guardar",
                                "b · clic central", "usar en el bloqueo",
                                "m", "rellenar / ajustar / centrar",
                                "r", "uno al azar",
                                "tab", "siguiente carpeta",
                                "a", "añadir carpeta",
                                "s", "incluir subcarpetas",
                                "/", "buscar por nombre",
                                "esc", "cerrar"
                            ]
                            Text {
                                required property string modelData
                                required property int index
                                text: modelData
                                color: index % 2 ? root.cSuave : root.cTexto
                                font.family: index % 2 ? root.fUi : root.fMono
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }
        }
    }

    // ── piezas ─────────────────────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string texto
        property string ruta: ""
        property bool activa: false
        property bool quitable: false
        signal pulsado()
        signal quitar()
        height: 30
        width: fila.width + 24
        radius: 8
        color: activa ? "#14ffffff" : (area.containsMouse ? "#0affffff" : "transparent")
        border.color: activa ? root.cBorde : "transparent"
        Row {
            id: fila
            anchors.centerIn: parent
            spacing: 8
            Text {
                text: chip.texto
                color: chip.activa ? root.cTexto : (area.containsMouse ? root.cTexto : root.cSuave)
                font.family: root.fUi; font.pixelSize: 13
                font.weight: chip.activa ? Font.Medium : Font.Normal
            }
            Text {
                visible: chip.quitable && area.containsMouse
                text: "×"
                color: equis.containsMouse ? "#d0665a" : root.cTenue
                font.family: root.fUi; font.pixelSize: 14
                MouseArea { id: equis; anchors.fill: parent; anchors.margins: -5; hoverEnabled: true; onClicked: chip.quitar() }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            z: -1
            onClicked: { chip.pulsado(); root.enfocarGrid() }
        }
    }

    component Opcion: Text {
        id: op
        property string texto
        property string pista: ""
        property bool activa: true
        signal pulsado()
        text: texto
        color: oa.containsMouse ? root.cTexto : (activa ? root.cSuave : root.cTenue)
        font.family: root.fUi; font.pixelSize: 13
        font.strikeout: false
        Rectangle {   // subrayado fino cuando está activa
            visible: op.activa && op.texto === "subcarpetas"
            anchors { left: parent.left; right: parent.right; top: parent.bottom; topMargin: 3 }
            height: 1; color: "#55ffffff"
        }
        MouseArea { id: oa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { op.pulsado(); root.enfocarGrid() } }
    }
}
