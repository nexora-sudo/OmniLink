import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../communication/identity.dart';
import '../communication/link_node.dart';
import '../models/models.dart';
import '../persistence/local_repository.dart';
import '../services/discovery_service.dart';
import '../services/platform_service.dart';
import '../services/save_service.dart';
import 'glass.dart';
import '../services/app_language.dart';

class OmniLinkApp extends StatefulWidget {
  const OmniLinkApp({super.key});
  @override
  State<OmniLinkApp> createState() => _OmniLinkAppState();
}

class _OmniLinkAppState extends State<OmniLinkApp> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  final messenger = GlobalKey<ScaffoldMessengerState>();
  LocalRepository? repository;
  LinkNode? node;
  DiscoveryService? discovery;
  final subscriptions = <StreamSubscription>[];
  ThemeMode themeMode = ThemeMode.system;
  int page = 0;
  String? fatal, selectedPeer;
  List<String> addresses = [];
  Map<String, dynamic> localInfo = {};
  final textController = TextEditingController();
  final receivedTexts = <Map<String, String>>[];
  final savingFiles = <String>{};
  bool discovering = true,
      autoClipboard = false,
      startup = false,
      dragging = false;
  bool _approvalActive = false, _clipboardBusy = false, _sendingFiles = false;
  String? _lastClipboard;
  Timer? clipboardTimer;
  Peer? get peer => node?.peers[selectedPeer];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(initialize()),
    );
  }

  Future<void> initialize() async {
    try {
      final support = await getApplicationSupportDirectory();
      repository = LocalRepository(p.join(support.path, 'omnilink.sqlite'));
      final repo = repository!;
      AppLanguage.load(repo.getSetting('language'));
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == repo.getSetting('theme'),
        orElse: () => ThemeMode.system,
      );
      discovering = repo.getSetting('discovery') != 'false';
      autoClipboard =
          Platform.isWindows && repo.getSetting('autoClipboard') == 'true';
      final defaultDirectory = Platform.isWindows
          ? await getDownloadsDirectory()
          : await getApplicationDocumentsDirectory();
      final destination = Directory(
        repo.getSetting('downloads') ??
            p.join(defaultDirectory!.path, 'OmniLink'),
      );
      final identity = await Identity.load(repo);
      final n = LinkNode(
        identity: identity,
        repository: repo,
        downloads: destination,
        name: repo.getSetting('name') ?? Platform.localHostname,
        approve: approve,
        deviceInfo: () =>
            PlatformService.info(node?.downloads.path ?? destination.path),
      );
      n.clipboardEnabled = repo.getSetting('clipboard') != 'false';
      n.textHistory = repo.getSetting('textHistory') == 'true';
      subscriptions.add(
        n.changes.listen((_) {
          if (mounted) setState(() {});
        }),
      );
      subscriptions.add(n.errors.listen(showMessage));
      subscriptions.add(
        n.incomingTexts.listen((text) {
          receivedTexts.insert(0, text);
          if (receivedTexts.length > 100) receivedTexts.removeLast();
          showMessage(
            tr(
              'Texto recebido de ${text['peer']}. Abra Textos para copiar.',
              "Text received from ${text['peer']}. Open Text to copy.",
            ),
          );
          if (mounted) setState(() {});
        }),
      );
      node = n;
      await n.start();
      addresses = await DiscoveryService.addresses();
      localInfo = await PlatformService.info(destination.path);
      startup = await PlatformService.startupEnabled();
      discovery = DiscoveryService(n);
      if (discovering) {
        try {
          await discovery!.start();
        } catch (e) {
          showMessage(
            tr(
              'mDNS indisponível. Use conexão manual. $e',
              "mDNS unavailable. Use a manual connection. $e",
            ),
          );
        }
      }
      clipboardTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(syncClipboard()),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(
          () => fatal = tr(
            'Não foi possível iniciar o OmniLink.\n$e',
            "Could not start OmniLink.\n$e",
          ),
        );
      }
    }
  }

  void showMessage(String message) => messenger.currentState?.showSnackBar(
    SnackBar(content: Text(AppLanguage.message(message))),
  );
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      showMessage(e.toString());
    }
  }

  Future<bool> approve(String title, String message) async {
    final context = navigator.currentContext;
    if (context == null ||
        _approvalActive ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    _approvalActive = true;
    Timer? timeout;
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) {
              timeout ??= Timer(const Duration(seconds: 55), () {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(false);
                }
              });
              return AlertDialog(
                title: Text(AppLanguage.message(title)),
                content: Text(AppLanguage.message(message)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(tr('Recusar', "Decline")),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(tr('Permitir', "Allow")),
                  ),
                ],
              );
            },
          ) ??
          false;
    } finally {
      timeout?.cancel();
      _approvalActive = false;
    }
  }

  Future<void> syncClipboard() async {
    if (!autoClipboard ||
        !Platform.isWindows ||
        node?.clipboardEnabled != true ||
        peer?.status != 'conectado' ||
        _clipboardBusy) {
      return;
    }
    _clipboardBusy = true;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text != null && text.isNotEmpty && text != _lastClipboard) {
        await node!.sendText(peer!, text);
        _lastClipboard = text;
      }
    } catch (e) {
      autoClipboard = false;
      repository!.setSetting('autoClipboard', 'false');
      showMessage(tr('Sincronização pausada: $e', "Clipboard sync paused: $e"));
      setState(() {});
    } finally {
      _clipboardBusy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && node != null) {
      unawaited(
        run(() async {
          addresses = await DiscoveryService.addresses();
          localInfo = await PlatformService.info(node!.downloads.path);
          await node!.poll();
          if (mounted) setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    clipboardTimer?.cancel();
    for (final s in subscriptions) {
      unawaited(s.cancel());
    }
    unawaited(discovery?.stop() ?? Future<void>.value());
    unawaited(node?.close() ?? Future<void>.value());
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OmniLink',
    debugShowCheckedModeBanner: false,
    navigatorKey: navigator,
    scaffoldMessengerKey: messenger,
    theme: omniTheme(Brightness.light),
    darkTheme: omniTheme(Brightness.dark),
    themeMode: themeMode,
    locale: Locale(AppLanguage.code),
    supportedLocales: const [Locale('en'), Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Builder(
      builder: (context) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? [
                      const Color(0xff081422),
                      const Color(0xff13333c),
                      const Color(0xff161b35),
                    ]
                  : [
                      const Color(0xffe2f3f0),
                      const Color(0xffeff2fa),
                      const Color(0xffdce7ef),
                    ],
            ),
          ),
          child: fatal != null
              ? Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: SelectableText(
                        tr(
                          '$fatal\n\nVerifique permissões, armazenamento e se a porta 45832 está livre. Reinicie o aplicativo.',
                          "$fatal\n\nCheck permissions, storage, and whether port 45832 is available. Restart the application.",
                        ),
                      ),
                    ),
                  ),
                )
              : node == null || discovery == null
              ? Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 24),
                        Text(
                          tr(
                            'Preparando sua conexão privada…',
                            "Preparing your private connection…",
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 850;
                    return Scaffold(
                      body: SafeArea(
                        child: Row(
                          children: [
                            if (wide)
                              Padding(
                                padding: const EdgeInsets.all(20),
                                child: Glass(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                    horizontal: 10,
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(Icons.hub_rounded, size: 36),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'OmniLink',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 32),
                                      Expanded(
                                        child: NavigationRail(
                                          backgroundColor: Colors.transparent,
                                          selectedIndex: page,
                                          labelType:
                                              NavigationRailLabelType.all,
                                          onDestinationSelected: (value) =>
                                              setState(() => page = value),
                                          destinations: [
                                            NavigationRailDestination(
                                              icon: const Icon(
                                                Icons.devices_rounded,
                                              ),
                                              label: Text(
                                                tr('Dispositivos', "Devices"),
                                              ),
                                            ),
                                            NavigationRailDestination(
                                              icon: const Icon(
                                                Icons.swap_vert_rounded,
                                              ),
                                              label: Text(
                                                tr('Arquivos', "Files"),
                                              ),
                                            ),
                                            NavigationRailDestination(
                                              icon: const Icon(
                                                Icons.notes_rounded,
                                              ),
                                              label: Text(tr('Textos', "Text")),
                                            ),
                                            NavigationRailDestination(
                                              icon: const Icon(
                                                Icons.tune_rounded,
                                              ),
                                              label: Text(
                                                tr('Ajustes', "Settings"),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        tr('0.1.1 Alpha', "0.1.1 Alpha"),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            Expanded(
                              child: DropTarget(
                                enable: Platform.isWindows,
                                onDragEntered: (_) =>
                                    setState(() => dragging = true),
                                onDragExited: (_) =>
                                    setState(() => dragging = false),
                                onDragDone: (details) {
                                  setState(() => dragging = false);
                                  unawaited(
                                    sendPaths(
                                      details.files.map((f) => f.path).toList(),
                                    ),
                                  );
                                },
                                child: Stack(
                                  children: [
                                    Column(
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            wide ? 12 : 24,
                                            24,
                                            24,
                                            16,
                                          ),
                                          child: Row(
                                            children: [
                                              if (!wide)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    right: 12,
                                                  ),
                                                  child: Icon(
                                                    Icons.hub_rounded,
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  [
                                                    tr(
                                                      'Dispositivos',
                                                      "Devices",
                                                    ),
                                                    tr(
                                                      'Transferências',
                                                      "Transfers",
                                                    ),
                                                    tr(
                                                      'Textos compartilhados',
                                                      "Shared text",
                                                    ),
                                                    tr(
                                                      'Configurações',
                                                      "Settings",
                                                    ),
                                                  ][page],
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: tr(
                                                  'Atualizar conexões',
                                                  "Refresh connections",
                                                ),
                                                onPressed: () =>
                                                    run(node!.poll),
                                                icon: const Icon(
                                                  Icons.refresh_rounded,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            child: SingleChildScrollView(
                                              key: ValueKey(page),
                                              padding: EdgeInsets.fromLTRB(
                                                wide ? 12 : 24,
                                                0,
                                                24,
                                                24,
                                              ),
                                              child: [
                                                devices(context),
                                                files(context),
                                                texts(context),
                                                settings(context),
                                              ][page],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (dragging)
                                      Positioned.fill(
                                        child: ColoredBox(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(alpha: .95),
                                          child: Center(
                                            child: Text(
                                              tr(
                                                'Solte para enviar ao dispositivo selecionado',
                                                "Drop to send to the selected device",
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      bottomNavigationBar: wide
                          ? null
                          : NavigationBar(
                              selectedIndex: page,
                              onDestinationSelected: (value) =>
                                  setState(() => page = value),
                              destinations: [
                                NavigationDestination(
                                  icon: const Icon(Icons.devices_rounded),
                                  label: tr('Dispositivos', "Devices"),
                                ),
                                NavigationDestination(
                                  icon: const Icon(Icons.swap_vert_rounded),
                                  label: tr('Arquivos', "Files"),
                                ),
                                NavigationDestination(
                                  icon: const Icon(Icons.notes_rounded),
                                  label: tr('Textos', "Text"),
                                ),
                                NavigationDestination(
                                  icon: const Icon(Icons.tune_rounded),
                                  label: tr('Ajustes', "Settings"),
                                ),
                              ],
                            ),
                    );
                  },
                ),
        );
      },
    ),
  );

  Widget devices(BuildContext context) {
    final n = node!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    tr(
                      'SUA REDE. SEUS DISPOSITIVOS.',
                      "YOUR NETWORK. YOUR DEVICES.",
                    ),
                    style: const TextStyle(fontSize: 11, letterSpacing: 1.8),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                tr(
                  'Tudo perto.\nTudo conectado.',
                  "Everything nearby.\nEverything connected.",
                ),
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(
                  'Arquivos e textos entre seu computador e celular, pela rede local.',
                  "Files and text between your computer and phone, over your local network.",
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => run(showInvite),
                    icon: const Icon(Icons.qr_code_rounded),
                    label: Text(tr('Criar convite', "Create invitation")),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => pairDialog(),
                    icon: const Icon(Icons.add_link_rounded),
                    label: Text(
                      tr('Conectar / IP manual', "Connect / Manual IP"),
                    ),
                  ),
                  if (Platform.isAndroid)
                    OutlinedButton.icon(
                      onPressed: () => run(scan),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: Text(tr('Ler QR Code', "Scan QR code")),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SelectableText(
                tr(
                  '${n.name} • ${addresses.isEmpty ? 'Sem IPv4 local disponível' : addresses.join(' / ')}:${n.port}',
                  "${n.name} • ${addresses.isEmpty ? 'No local IPv4 available' : addresses.join(' / ')}:${n.port}",
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        section(
          tr('Seus dispositivos', "Your devices"),
          tr('${n.peers.length} pareados', "${n.peers.length} paired"),
        ),
        if (n.peers.isEmpty)
          Glass(
            child: Text(
              tr(
                'Nenhum dispositivo pareado. Abra o OmniLink nos dois aparelhos e crie um convite em um deles.',
                "No devices paired. Open OmniLink on both devices and create an invitation on one of them.",
              ),
            ),
          ),
        ...n.peers.values.map(
          (device) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        device.info['os'] == 'android'
                            ? Icons.smartphone_rounded
                            : Icons.computer_rounded,
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              device.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              tr(
                                '${device.host}:${device.port} • ${device.status}',
                                "${device.host}:${device.port} • ${statusLabel(device.status)}",
                              ),
                            ),
                          ],
                        ),
                      ),
                      RadioGroup<String>(
                        groupValue: selectedPeer,
                        onChanged: (value) =>
                            setState(() => selectedPeer = value),
                        child: Radio<String>(value: device.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            selectedPeer = device.id;
                            page = 1;
                          });
                        },
                        icon: const Icon(Icons.upload_file_rounded),
                        label: Text(tr('Enviar arquivos', "Send files")),
                      ),
                      TextButton(
                        onPressed: () => infoDialog(device),
                        child: Text(tr('Detalhes', "Details")),
                      ),
                      TextButton(
                        onPressed: () => run(() async {
                          if (await approve(
                            tr('Remover dispositivo?', "Remove device?"),
                            tr(
                              'O acesso de ${device.name} será revogado neste aparelho.',
                              "Access for ${device.name} will be revoked on this device.",
                            ),
                          )) {
                            await n.forget(device);
                            if (selectedPeer == device.id) {
                              setState(() => selectedPeer = null);
                            }
                          }
                        }),
                        child: Text(tr('Remover', "Remove")),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        section(
          tr('Na mesma rede', "On the same network"),
          discovering
              ? 'mDNS'
              : tr('Descoberta desativada', "Discovery disabled"),
        ),
        ...discovery!.nearby.values
            .where((d) => !n.peers.containsKey(d.id))
            .map(
              (d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Glass(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(d.name),
                    subtitle: Text(
                      tr(
                        '${d.host}:${d.port} • não pareado',
                        "${d.host}:${d.port} • not paired",
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: tr('Parear', "Pair"),
                      icon: const Icon(Icons.add_link),
                      onPressed: () => pairDialog(host: d.host, port: d.port),
                    ),
                  ),
                ),
              ),
            ),
        if (discovery!.nearby.values
            .where((d) => !n.peers.containsKey(d.id))
            .isEmpty)
          Text(
            tr(
              'Nenhum novo dispositivo detectado. A conexão manual também funciona quando o roteador bloqueia mDNS.',
              "No new devices detected. Manual connection also works when the router blocks mDNS.",
            ),
          ),
      ],
    );
  }

  Widget section(String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
        Text(subtitle, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
  Widget peerSelector() => DropdownButtonFormField<String>(
    initialValue: peer?.id,
    key: ValueKey(selectedPeer),
    decoration: InputDecoration(
      labelText: tr('Dispositivo de destino', "Destination device"),
    ),
    items: node!.peers.values
        .map(
          (p) => DropdownMenuItem(
            value: p.id,
            child: Text(
              tr(
                '${p.name} • ${p.status}',
                "${p.name} • ${statusLabel(p.status)}",
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(),
    onChanged: (value) => setState(() => selectedPeer = value),
  );
  Widget files(BuildContext context) {
    final list = node!.transfers.values.toList()
      ..sort((a, b) => b.updated.compareTo(a.updated));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              peerSelector(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _sendingFiles || peer == null
                    ? null
                    : () => run(() async {
                        final result = await FilePicker.platform.pickFiles(
                          allowMultiple: true,
                        );
                        if (result == null) return;
                        final paths = result.files
                            .map((f) => f.path)
                            .whereType<String>()
                            .toList();
                        if (paths.length != result.files.length) {
                          showMessage(
                            tr(
                              'Alguns arquivos não estão disponíveis localmente.',
                              "Some files are not available locally.",
                            ),
                          );
                        }
                        await sendPaths(paths);
                      }),
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(
                  _sendingFiles
                      ? tr('Enviando arquivos…', "Sending files…")
                      : tr('Selecionar arquivos', "Select files"),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                Platform.isWindows
                    ? tr(
                        'Ou arraste arquivos para esta janela. Até 4 GiB por arquivo.',
                        "Or drag files into this window. Up to 4 GiB per file.",
                      )
                    : tr(
                        'Seleção pelo sistema. Mantenha o aplicativo aberto durante a transferência.',
                        "Select files using the system picker. Keep the app open during transfers.",
                      ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                tr(
                  'Destino: ${node!.downloads.path}',
                  "Destination: ${node!.downloads.path}",
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        section(
          tr('Atividade e histórico', "Activity and history"),
          tr('${list.length} arquivos', "${list.length} files"),
        ),
        if (list.isEmpty)
          Glass(
            child: Text(
              tr(
                'Suas transferências aparecerão aqui, com progresso e verificação de integridade.',
                "Your transfers will appear here, with progress and integrity verification.",
              ),
            ),
          ),
        ...list.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        t.incoming
                            ? Icons.download_rounded
                            : Icons.upload_rounded,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (t.state != 'concluído' && t.state != 'cancelado')
                        IconButton(
                          tooltip: tr('Cancelar', "Cancel"),
                          onPressed: () => run(() => node!.cancel(t)),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: t.progress.clamp(0.0, 1.0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    tr(
                      '${t.state} • ${(t.progress * 100).toStringAsFixed(1)}% • ${(t.done / 1048576).toStringAsFixed(1)} / ${(t.size / 1048576).toStringAsFixed(1)} MiB',
                      "${statusLabel(t.state)} • ${(t.progress * 100).toStringAsFixed(1)}% • ${(t.done / 1048576).toStringAsFixed(1)} / ${(t.size / 1048576).toStringAsFixed(1)} MiB",
                    ),
                  ),
                  if (t.speed > 0)
                    Text(
                      tr(
                        '${(t.speed / 1000000).toStringAsFixed(2)} MB/s • ${t.eta}s restantes (estimativa)',
                        "${(t.speed / 1000000).toStringAsFixed(2)} MB/s • ${t.eta}s remaining (estimated)",
                      ),
                    ),
                  if (t.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        AppLanguage.message(t.error!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (t.state == 'concluído')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        tr('SHA-256 verificado', "SHA-256 verified"),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (!t.incoming && !t.busy && t.state != 'concluído')
                        TextButton(
                          onPressed: () => run(() => node!.resume(t)),
                          child: Text(tr('Retomar', "Resume")),
                        ),
                      if (t.incoming && !t.busy && t.state != 'concluído')
                        TextButton(
                          onPressed: () => run(() => node!.discardPartial(t)),
                          child: Text(
                            tr('Excluir parcial', "Delete partial file"),
                          ),
                        ),
                      if (t.incoming && t.state == 'concluído')
                        TextButton.icon(
                          onPressed: () => run(() async {
                            await SharePlus.instance.share(
                              ShareParams(files: [XFile(t.path)]),
                            );
                          }),
                          icon: const Icon(Icons.share_outlined),
                          label: Text(tr('Compartilhar', "Share")),
                        ),
                      if (t.incoming && t.state == 'concluído') ...[
                        if (Platform.isAndroid &&
                            SaveService.isGalleryMedia(t.name))
                          TextButton.icon(
                            onPressed: savingFiles.contains(t.id)
                                ? null
                                : () => saveReceived(t, gallery: true),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: Text(
                              tr('Salvar na galeria', "Save to gallery"),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: savingFiles.contains(t.id)
                              ? null
                              : () => saveReceived(t, gallery: false),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            savingFiles.contains(t.id)
                                ? tr('Salvando…', "Saving…")
                                : tr(
                                    'Salvar em Downloads',
                                    "Save to Downloads",
                                  ),
                          ),
                        ),
                      ],
                      if (t.incoming &&
                          t.state == 'concluído' &&
                          Platform.isAndroid)
                        TextButton(
                          onPressed: () =>
                              run(() => PlatformService.exportFile(t.path)),
                          child: Text(tr('Salvar em…', "Save as…")),
                        ),
                      if (t.state == 'concluído')
                        TextButton(
                          onPressed: () => run(() async {
                            await Clipboard.setData(
                              ClipboardData(text: t.path),
                            );
                            showMessage(tr('Caminho copiado.', "Path copied."));
                          }),
                          child: Text(tr('Copiar caminho', "Copy path")),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> saveReceived(Transfer transfer, {required bool gallery}) async {
    setState(() => savingFiles.add(transfer.id));
    try {
      final location = await SaveService.save(transfer.path, gallery: gallery);
      showMessage(
        gallery
            ? tr(
                'Salvo na galeria, no álbum OmniLink.',
                "Saved to the OmniLink gallery album.",
              )
            : tr('Arquivo salvo em $location', "File saved to $location"),
      );
    } catch (error) {
      showMessage(
        tr('Não foi possível salvar: $error', "Could not save: $error"),
      );
    } finally {
      if (mounted) setState(() => savingFiles.remove(transfer.id));
    }
  }

  Future<void> sendPaths(List<String> paths) async {
    final target = peer;
    if (target == null) {
      showMessage(
        tr(
          'Selecione um dispositivo de destino.',
          "Select a destination device.",
        ),
      );
      return;
    }
    if (_sendingFiles) {
      showMessage(
        tr('Aguarde o envio atual.', "Wait for the current transfer."),
      );
      return;
    }
    setState(() {
      page = 1;
      _sendingFiles = true;
    });
    try {
      for (final path in paths) {
        if (!await File(path).exists()) {
          showMessage(
            tr('Arquivo indisponível: $path', "File unavailable: $path"),
          );
          continue;
        }
        await run(() async {
          await node!.sendFile(target, File(path));
        });
      }
    } finally {
      if (mounted) setState(() => _sendingFiles = false);
    }
  }

  Widget texts(BuildContext context) {
    final records = node!.textHistory
        ? repository!
              .texts()
              .map((r) => {'peer': '${r['peer']}', 'text': '${r['text']}'})
              .toList()
        : receivedTexts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Glass(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              peerSelector(),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                minLines: 4,
                maxLines: 10,
                maxLength: 16000,
                decoration: InputDecoration(
                  labelText: tr('Texto para compartilhar', "Text to share"),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: peer == null || !node!.clipboardEnabled
                        ? null
                        : () => run(() async {
                            await node!.sendText(peer!, textController.text);
                            showMessage(
                              tr('Texto entregue.', "Text delivered."),
                            );
                          }),
                    icon: const Icon(Icons.send_rounded),
                    label: Text(tr('Enviar texto', "Send text")),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => run(() async {
                      textController.text =
                          (await Clipboard.getData(
                            Clipboard.kTextPlain,
                          ))?.text ??
                          '';
                    }),
                    icon: const Icon(Icons.paste_rounded),
                    label: Text(tr('Colar', "Paste")),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                tr(
                  'Textos recebidos só entram na sua área de transferência quando você toca em Copiar. No Android, a leitura é manual.',
                  "Received text is only copied to your clipboard when you tap Copy. On Android, clipboard reading is manual.",
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        section(
          tr('Textos recebidos / histórico', "Received text / history"),
          node!.textHistory
              ? tr('Salvo neste aparelho', "Saved on this device")
              : tr('Apenas nesta sessão', "Only in this session"),
        ),
        if (records.isEmpty)
          Glass(
            child: Text(
              tr(
                'Nenhum texto compartilhado nesta sessão.',
                "No text shared in this session.",
              ),
            ),
          ),
        ...records.map(
          (r) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Glass(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['peer']!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(r['text']!),
                  TextButton.icon(
                    onPressed: () => run(() async {
                      _lastClipboard = r['text'];
                      await Clipboard.setData(ClipboardData(text: r['text']!));
                      showMessage(tr('Texto copiado.', "Text copied."));
                    }),
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(tr('Copiar', "Copy")),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget settings(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Glass(
        child: Column(
          children: [
            DropdownButtonFormField<ThemeMode>(
              initialValue: themeMode,
              decoration: InputDecoration(
                labelText: tr('Aparência', "Appearance"),
              ),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(tr('Automático', "System")),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(tr('Claro', "Light")),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(tr('Escuro', "Dark")),
                ),
              ],
              onChanged: (m) {
                setState(() => themeMode = m!);
                repository!.setSetting('theme', m!.name);
              },
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(AppLanguage.code),
              initialValue: AppLanguage.code,
              decoration: InputDecoration(labelText: tr('Idioma', 'Language')),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(
                  value: 'pt',
                  child: Text('Português (Brasil)'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                repository!.setSetting('language', value);
                setState(() => AppLanguage.load(value));
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Nome do dispositivo', "Device name")),
              subtitle: Text(node!.name),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => run(rename),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Pasta de recebimento', "Receive folder")),
              subtitle: Text(node!.downloads.path),
              trailing: Platform.isWindows
                  ? const Icon(Icons.folder_open_rounded)
                  : null,
              onTap: Platform.isWindows
                  ? () => run(() async {
                      final directory = await FilePicker.platform
                          .getDirectoryPath();
                      if (directory == null) return;
                      node!.downloads = Directory(directory);
                      repository!.setSetting('downloads', directory);
                      setState(() {});
                    })
                  : null,
            ),
            if (Platform.isAndroid)
              Text(
                tr(
                  'Após receber, use Salvar na galeria para fotos e vídeos ou Salvar em Downloads para qualquer arquivo. Salvar em… permite escolher outra pasta.',
                  "After receiving a file, use Save to gallery for photos and videos or Save to Downloads for any file. Save as… lets you choose another folder.",
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Descoberta automática', "Automatic discovery")),
              subtitle: Text(
                tr(
                  'Localiza e anuncia dispositivos via mDNS',
                  "Find and advertise devices using mDNS",
                ),
              ),
              value: discovering,
              onChanged: (v) => run(() async {
                if (v) {
                  await discovery!.start();
                } else {
                  await discovery!.stop();
                }
                repository!.setSetting('discovery', '$v');
                setState(() => discovering = v);
              }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Compartilhar textos', "Share text")),
              value: node!.clipboardEnabled,
              onChanged: (v) {
                setState(() => node!.clipboardEnabled = v);
                repository!.setSetting('clipboard', '$v');
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                tr('Salvar histórico de textos', "Save text history"),
              ),
              subtitle: Text(
                tr(
                  'Desativado por padrão; conteúdo salvo localmente sem criptografia adicional',
                  "Disabled by default; content is stored locally without additional encryption",
                ),
              ),
              value: node!.textHistory,
              onChanged: (v) {
                setState(() => node!.textHistory = v);
                repository!.setSetting('textHistory', '$v');
              },
            ),
            TextButton(
              onPressed: () {
                repository!.clearTexts();
                setState(receivedTexts.clear);
              },
              child: Text(
                tr('Apagar histórico de textos', "Clear text history"),
              ),
            ),
            if (Platform.isWindows)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr(
                    'Enviar área de transferência automaticamente',
                    "Send clipboard automatically",
                  ),
                ),
                subtitle: Text(
                  tr(
                    'Envia qualquer texto copiado ao dispositivo selecionado enquanto o app está aberto. Pode incluir senhas.',
                    "Sends any copied text to the selected device while the app is open. May include passwords.",
                  ),
                ),
                value: autoClipboard,
                onChanged: (v) {
                  setState(() => autoClipboard = v);
                  repository!.setSetting('autoClipboard', '$v');
                },
              ),
            if (Platform.isWindows)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('Iniciar com o Windows', "Launch at Windows startup"),
                ),
                value: startup,
                onChanged: (v) => run(() async {
                  await PlatformService.setStartup(v);
                  setState(() => startup = v);
                }),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Glass(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Este dispositivo', "This device"),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              '${localInfo['os'] ?? Platform.operatingSystem}\n${localInfo['version'] ?? Platform.operatingSystemVersion}',
            ),
            Text(
              tr(
                'Bateria: ${localInfo['battery'] == null ? 'não disponível' : '${localInfo['battery']}%'}',
                "Battery: ${localInfo['battery'] == null ? 'not available' : '${localInfo['battery']}%'}",
              ),
            ),
            Text(
              tr(
                'Espaço disponível: ${localInfo['freeBytes'] == null ? 'não disponível' : '${(localInfo['freeBytes'] / 1073741824).toStringAsFixed(1)} GiB'}',
                "Available space: ${localInfo['freeBytes'] == null ? 'not available' : '${(localInfo['freeBytes'] / 1073741824).toStringAsFixed(1)} GiB'}",
              ),
            ),
            const SizedBox(height: 20),
            Text(
              tr('OmniLink 0.1.1 Alpha', "OmniLink 0.1.1 Alpha"),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              tr(
                'Código aberto • Licença MIT\nSem contas, servidores externos ou telemetria.\nMantenha o app aberto nos dois aparelhos durante o uso.',
                "Open source • MIT License\nNo accounts, external servers, or telemetry.\nKeep the app open on both devices during use.",
              ),
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'OmniLink',
                applicationVersion: tr('0.1.1 Alpha', "0.1.1 Alpha"),
                applicationLegalese:
                    'MIT License • Copyright 2026 OmniLink contributors',
              ),
              child: Text(
                tr('Licenças de código aberto', "Open-source licenses"),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> rename() async {
    final controller = TextEditingController(text: node!.name);
    final value = await showDialog<String>(
      context: navigator.currentContext!,
      builder: (c) => AlertDialog(
        title: Text(tr('Nome do dispositivo', "Device name")),
        content: TextField(controller: controller, maxLength: 80),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Cancelar', "Cancel")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: Text(tr('Salvar', "Save")),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    node!.name = value;
    repository!.setSetting('name', value);
    if (discovering) await discovery!.start();
    setState(() {});
  }

  Future<void> showInvite() async {
    addresses = await DiscoveryService.addresses();
    if (addresses.isEmpty) {
      throw LinkException(
        tr(
          'Conecte-se a uma rede Wi-Fi ou Ethernet local.',
          "Connect to a local Wi-Fi or Ethernet network.",
        ),
      );
    }
    var host = addresses.first;
    var invite = node!.createInvite(host);
    try {
      await showDialog<void>(
        context: navigator.currentContext!,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: Text(tr('Conectar um dispositivo', "Connect a device")),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(
                        'Leia este QR no outro aparelho. Convite válido por 5 minutos e uma única tentativa.',
                        "Scan this QR code on the other device. The invitation is valid for 5 minutes and a single attempt.",
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: host,
                      items: addresses
                          .map(
                            (a) => DropdownMenuItem(value: a, child: Text(a)),
                          )
                          .toList(),
                      onChanged: (value) => update(() {
                        host = value!;
                        invite = node!.createInvite(host);
                      }),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(data: invite.encode(), size: 230),
                    ),
                    TextButton.icon(
                      onPressed: () => run(() async {
                        _lastClipboard = invite.encode();
                        await Clipboard.setData(
                          ClipboardData(text: invite.encode()),
                        );
                        showMessage(
                          tr(
                            'Convite copiado. Compartilhe apenas com o outro aparelho.',
                            "Invitation copied. Share it only with the other device.",
                          ),
                        );
                      }),
                      icon: const Icon(Icons.copy),
                      label: Text(tr('Copiar convite', "Copy invitation")),
                    ),
                    ExpansionTile(
                      title: Text(
                        tr(
                          'Dados para conexão manual',
                          "Manual connection details",
                        ),
                      ),
                      children: [
                        SelectableText(
                          tr(
                            'IP: $host\nPorta: ${invite.port}\nCertificado SHA-256:\n${invite.fingerprint}\nCódigo secreto:\n${invite.secret}',
                            "IP: $host\nPort: ${invite.port}\nSHA-256 certificate:\n${invite.fingerprint}\nSecret code:\n${invite.secret}",
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(
                  tr('Fechar e revogar convite', "Close and revoke invitation"),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      node!.revokeInvite();
    }
  }

  Future<void> pairDialog({String? host, int? port}) async {
    final input = TextEditingController();
    final ip = TextEditingController(text: host);
    final portInput = TextEditingController(text: '${port ?? 45832}');
    final fingerprint = TextEditingController();
    final secret = TextEditingController();
    var manual = host != null;
    var busy = false;
    String? error;
    await showDialog<void>(
      context: navigator.currentContext!,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(tr('Parear dispositivo', "Pair device")),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(
                      'Crie um convite no outro aparelho. Confirme o pareamento também na tela dele.',
                      "Create an invitation on the other device. Confirm pairing on its screen too.",
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      tr(
                        'Informar IP e credenciais',
                        "Enter IP and credentials",
                      ),
                    ),
                    value: manual,
                    onChanged: busy ? null : (v) => update(() => manual = v),
                  ),
                  if (!manual)
                    TextField(
                      controller: input,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Cole o convite OmniLink',
                          "Paste the OmniLink invitation",
                        ),
                      ),
                    ),
                  if (manual) ...[
                    TextField(
                      controller: ip,
                      decoration: InputDecoration(
                        labelText: tr('IPv4 local', "Local IPv4"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: portInput,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('Porta', "Port"),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fingerprint,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Certificado SHA-256 do convite',
                          "Invitation SHA-256 certificate",
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: secret,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Código secreto do convite',
                          "Invitation secret code",
                        ),
                      ),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(AppLanguage.message(error!)),
                    ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(c),
              child: Text(tr('Fechar', "Close")),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final invite = manual
                            ? Invite(
                                ip.text.trim(),
                                int.parse(portInput.text),
                                fingerprint.text.trim().toLowerCase(),
                                secret.text.trim(),
                              )
                            : Invite.parse(input.text.trim());
                        final result = await node!.pair(invite);
                        setState(() => selectedPeer = result.id);
                        if (c.mounted) Navigator.pop(c);
                        showMessage(
                          tr(
                            'Dispositivo pareado com segurança.',
                            "Device paired securely.",
                          ),
                        );
                      } catch (e) {
                        if (c.mounted) {
                          update(() {
                            busy = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              child: Text(tr('Conectar', "Connect")),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> scan() async {
    final value = await Navigator.of(
      navigator.currentContext!,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (value == null) return;
    final result = await node!.pair(Invite.parse(value));
    setState(() => selectedPeer = result.id);
    showMessage(
      tr('Dispositivo pareado com segurança.', "Device paired securely."),
    );
  }

  void infoDialog(Peer device) => showDialog<void>(
    context: navigator.currentContext!,
    builder: (c) => AlertDialog(
      title: Text(device.name),
      content: SingleChildScrollView(
        child: SelectableText(
          tr(
            'Estado: ${device.status}\nIP: ${device.host}:${device.port}\nSistema: ${device.info['os'] ?? 'não disponível'}\nVersão: ${device.info['version'] ?? 'não disponível'}\nBateria: ${device.info['battery'] == null ? 'não disponível' : '${device.info['battery']}%'}\nEspaço livre: ${device.info['freeBytes'] == null ? 'não disponível' : '${(device.info['freeBytes'] / 1073741824).toStringAsFixed(1)} GiB'}\nÚltima conexão: ${device.lastSeen?.toLocal().toString() ?? 'não disponível'}\n\nCertificado SHA-256:\n${device.fingerprint}',
            "Status: ${statusLabel(device.status)}\nIP: ${device.host}:${device.port}\nSystem: ${device.info['os'] ?? 'not available'}\nVersion: ${device.info['version'] ?? 'not available'}\nBattery: ${device.info['battery'] == null ? 'not available' : '${device.info['battery']}%'}\nFree space: ${device.info['freeBytes'] == null ? 'not available' : '${(device.info['freeBytes'] / 1073741824).toStringAsFixed(1)} GiB'}\nLast connection: ${device.lastSeen?.toLocal().toString() ?? 'not available'}\n\nSHA-256 certificate:\n${device.fingerprint}",
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr('Fechar', "Close")),
        ),
      ],
    ),
  );
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool done = false;
  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Ler convite OmniLink', "Scan OmniLink invitation")),
    ),
    body: MobileScanner(
      controller: controller,
      onDetect: (capture) {
        for (final code in capture.barcodes) {
          final value = code.rawValue;
          if (!done && value != null && value.startsWith('omnilink:')) {
            done = true;
            Navigator.pop(context, value);
            break;
          }
        }
      },
    ),
  );
}
