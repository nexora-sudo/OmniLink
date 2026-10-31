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
            'Texto recebido de ${text['peer']}. Abra Textos para copiar.',
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
          showMessage('mDNS indisponível. Use conexão manual. $e');
        }
      }
      clipboardTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(syncClipboard()),
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => fatal = 'Não foi possível iniciar o OmniLink.\n$e');
      }
    }
  }

  void showMessage(String message) =>
      messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
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
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Recusar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Permitir'),
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
      showMessage('Sincronização pausada: $e');
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
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
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
                        '$fatal\n\nVerifique permissões, armazenamento e se a porta 45832 está livre. Reinicie o aplicativo.',
                      ),
                    ),
                  ),
                )
              : node == null || discovery == null
              ? const Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 24),
                        Text('Preparando sua conexão privada…'),
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
                                          destinations: const [
                                            NavigationRailDestination(
                                              icon: Icon(Icons.devices_rounded),
                                              label: Text('Dispositivos'),
                                            ),
                                            NavigationRailDestination(
                                              icon: Icon(
                                                Icons.swap_vert_rounded,
                                              ),
                                              label: Text('Arquivos'),
                                            ),
                                            NavigationRailDestination(
                                              icon: Icon(Icons.notes_rounded),
                                              label: Text('Textos'),
                                            ),
                                            NavigationRailDestination(
                                              icon: Icon(Icons.tune_rounded),
                                              label: Text('Ajustes'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Text(
                                        '0.1.0 Alpha',
                                        style: TextStyle(fontSize: 12),
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
                                                    'Dispositivos',
                                                    'Transferências',
                                                    'Textos compartilhados',
                                                    'Configurações',
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
                                                tooltip: 'Atualizar conexões',
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
                                          child: const Center(
                                            child: Text(
                                              'Solte para enviar ao dispositivo selecionado',
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
                              destinations: const [
                                NavigationDestination(
                                  icon: Icon(Icons.devices_rounded),
                                  label: 'Dispositivos',
                                ),
                                NavigationDestination(
                                  icon: Icon(Icons.swap_vert_rounded),
                                  label: 'Arquivos',
                                ),
                                NavigationDestination(
                                  icon: Icon(Icons.notes_rounded),
                                  label: 'Textos',
                                ),
                                NavigationDestination(
                                  icon: Icon(Icons.tune_rounded),
                                  label: 'Ajustes',
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
              const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'SUA REDE. SEUS DISPOSITIVOS.',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.8),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Tudo perto.\nTudo conectado.',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Arquivos e textos entre seu computador e celular, pela rede local.',
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () => run(showInvite),
                    icon: const Icon(Icons.qr_code_rounded),
                    label: const Text('Criar convite'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => pairDialog(),
                    icon: const Icon(Icons.add_link_rounded),
                    label: const Text('Conectar / IP manual'),
                  ),
                  if (Platform.isAndroid)
                    OutlinedButton.icon(
                      onPressed: () => run(scan),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('Ler QR Code'),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SelectableText(
                '${n.name} • ${addresses.isEmpty ? 'Sem IPv4 local disponível' : addresses.join(' / ')}:${n.port}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        section('Seus dispositivos', '${n.peers.length} pareados'),
        if (n.peers.isEmpty)
          const Glass(
            child: Text(
              'Nenhum dispositivo pareado. Abra o OmniLink nos dois aparelhos e crie um convite em um deles.',
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
                              '${device.host}:${device.port} • ${device.status}',
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
                        label: const Text('Enviar arquivos'),
                      ),
                      TextButton(
                        onPressed: () => infoDialog(device),
                        child: const Text('Detalhes'),
                      ),
                      TextButton(
                        onPressed: () => run(() async {
                          if (await approve(
                            'Remover dispositivo?',
                            'O acesso de ${device.name} será revogado neste aparelho.',
                          )) {
                            await n.forget(device);
                            if (selectedPeer == device.id) {
                              setState(() => selectedPeer = null);
                            }
                          }
                        }),
                        child: const Text('Remover'),
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
          'Na mesma rede',
          discovering ? 'mDNS' : 'Descoberta desativada',
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
                    subtitle: Text('${d.host}:${d.port} • não pareado'),
                    trailing: IconButton(
                      tooltip: 'Parear',
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
          const Text(
            'Nenhum novo dispositivo detectado. A conexão manual também funciona quando o roteador bloqueia mDNS.',
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
    decoration: const InputDecoration(labelText: 'Dispositivo de destino'),
    items: node!.peers.values
        .map(
          (p) => DropdownMenuItem(
            value: p.id,
            child: Text(
              '${p.name} • ${p.status}',
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
                            'Alguns arquivos não estão disponíveis localmente.',
                          );
                        }
                        await sendPaths(paths);
                      }),
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(
                  _sendingFiles ? 'Enviando arquivos…' : 'Selecionar arquivos',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                Platform.isWindows
                    ? 'Ou arraste arquivos para esta janela. Até 4 GiB por arquivo.'
                    : 'Seleção pelo sistema. Mantenha o aplicativo aberto durante a transferência.',
              ),
              const SizedBox(height: 10),
              SelectableText(
                'Destino: ${node!.downloads.path}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        section('Atividade e histórico', '${list.length} arquivos'),
        if (list.isEmpty)
          const Glass(
            child: Text(
              'Suas transferências aparecerão aqui, com progresso e verificação de integridade.',
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
                          tooltip: 'Cancelar',
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
                    '${t.state} • ${(t.progress * 100).toStringAsFixed(1)}% • ${(t.done / 1048576).toStringAsFixed(1)} / ${(t.size / 1048576).toStringAsFixed(1)} MiB',
                  ),
                  if (t.speed > 0)
                    Text(
                      '${(t.speed / 1000000).toStringAsFixed(2)} MB/s • ${t.eta}s restantes (estimativa)',
                    ),
                  if (t.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        t.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (t.state == 'concluído')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'SHA-256 verificado',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (!t.incoming && !t.busy && t.state != 'concluído')
                        TextButton(
                          onPressed: () => run(() => node!.resume(t)),
                          child: const Text('Retomar'),
                        ),
                      if (t.incoming && !t.busy && t.state != 'concluído')
                        TextButton(
                          onPressed: () => run(() => node!.discardPartial(t)),
                          child: const Text('Excluir parcial'),
                        ),
                      if (t.incoming && t.state == 'concluído')
                        TextButton.icon(
                          onPressed: () => run(() async {
                            await SharePlus.instance.share(
                              ShareParams(files: [XFile(t.path)]),
                            );
                          }),
                          icon: const Icon(Icons.share_outlined),
                          label: const Text('Compartilhar'),
                        ),
                      if (t.incoming && t.state == 'concluído') ...[
                        if (Platform.isAndroid &&
                            SaveService.isGalleryMedia(t.name))
                          TextButton.icon(
                            onPressed: savingFiles.contains(t.id)
                                ? null
                                : () => saveReceived(t, gallery: true),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Salvar na galeria'),
                          ),
                        TextButton.icon(
                          onPressed: savingFiles.contains(t.id)
                              ? null
                              : () => saveReceived(t, gallery: false),
                          icon: const Icon(Icons.download_rounded),
                          label: Text(
                            savingFiles.contains(t.id)
                                ? 'Salvando…'
                                : 'Salvar em Downloads',
                          ),
                        ),
                      ],
                      if (t.incoming &&
                          t.state == 'concluído' &&
                          Platform.isAndroid)
                        TextButton(
                          onPressed: () =>
                              run(() => PlatformService.exportFile(t.path)),
                          child: const Text('Salvar em…'),
                        ),
                      if (t.state == 'concluído')
                        TextButton(
                          onPressed: () => run(() async {
                            await Clipboard.setData(
                              ClipboardData(text: t.path),
                            );
                            showMessage('Caminho copiado.');
                          }),
                          child: const Text('Copiar caminho'),
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
            ? 'Salvo na galeria, no álbum OmniLink.'
            : 'Arquivo salvo em $location',
      );
    } catch (error) {
      showMessage('Não foi possível salvar: $error');
    } finally {
      if (mounted) setState(() => savingFiles.remove(transfer.id));
    }
  }

  Future<void> sendPaths(List<String> paths) async {
    final target = peer;
    if (target == null) {
      showMessage('Selecione um dispositivo de destino.');
      return;
    }
    if (_sendingFiles) {
      showMessage('Aguarde o envio atual.');
      return;
    }
    setState(() {
      page = 1;
      _sendingFiles = true;
    });
    try {
      for (final path in paths) {
        if (!await File(path).exists()) {
          showMessage('Arquivo indisponível: $path');
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
                decoration: const InputDecoration(
                  labelText: 'Texto para compartilhar',
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
                            showMessage('Texto entregue.');
                          }),
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Enviar texto'),
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
                    label: const Text('Colar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Textos recebidos só entram na sua área de transferência quando você toca em Copiar. No Android, a leitura é manual.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        section(
          'Textos recebidos / histórico',
          node!.textHistory ? 'Salvo neste aparelho' : 'Apenas nesta sessão',
        ),
        if (records.isEmpty)
          const Glass(child: Text('Nenhum texto compartilhado nesta sessão.')),
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
                      showMessage('Texto copiado.');
                    }),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar'),
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
              decoration: const InputDecoration(labelText: 'Aparência'),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Automático'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Escuro')),
              ],
              onChanged: (m) {
                setState(() => themeMode = m!);
                repository!.setSetting('theme', m!.name);
              },
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Idioma'),
              subtitle: Text('Português (Brasil)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nome do dispositivo'),
              subtitle: Text(node!.name),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => run(rename),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Pasta de recebimento'),
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
              const Text(
                'Após receber, use Salvar na galeria para fotos e vídeos ou Salvar em Downloads para qualquer arquivo. Salvar em… permite escolher outra pasta.',
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Descoberta automática'),
              subtitle: const Text('Localiza e anuncia dispositivos via mDNS'),
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
              title: const Text('Compartilhar textos'),
              value: node!.clipboardEnabled,
              onChanged: (v) {
                setState(() => node!.clipboardEnabled = v);
                repository!.setSetting('clipboard', '$v');
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Salvar histórico de textos'),
              subtitle: const Text(
                'Desativado por padrão; conteúdo salvo localmente sem criptografia adicional',
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
              child: const Text('Apagar histórico de textos'),
            ),
            if (Platform.isWindows)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Enviar área de transferência automaticamente',
                ),
                subtitle: const Text(
                  'Envia qualquer texto copiado ao dispositivo selecionado enquanto o app está aberto. Pode incluir senhas.',
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
                title: const Text('Iniciar com o Windows'),
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
            const Text(
              'Este dispositivo',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              '${localInfo['os'] ?? Platform.operatingSystem}\n${localInfo['version'] ?? Platform.operatingSystemVersion}',
            ),
            Text(
              'Bateria: ${localInfo['battery'] == null ? 'não disponível' : '${localInfo['battery']}%'}',
            ),
            Text(
              'Espaço disponível: ${localInfo['freeBytes'] == null ? 'não disponível' : '${(localInfo['freeBytes'] / 1073741824).toStringAsFixed(1)} GiB'}',
            ),
            const SizedBox(height: 20),
            const Text(
              'OmniLink 0.1.0 Alpha',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const Text(
              'Código aberto • Licença MIT\nSem contas, servidores externos ou telemetria.\nMantenha o app aberto nos dois aparelhos durante o uso.',
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'OmniLink',
                applicationVersion: '0.1.0 Alpha',
                applicationLegalese:
                    'MIT License • Copyright 2026 OmniLink contributors',
              ),
              child: const Text('Licenças de código aberto'),
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
        title: const Text('Nome do dispositivo'),
        content: TextField(controller: controller, maxLength: 80),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Salvar'),
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
      throw LinkException('Conecte-se a uma rede Wi-Fi ou Ethernet local.');
    }
    var host = addresses.first;
    var invite = node!.createInvite(host);
    try {
      await showDialog<void>(
        context: navigator.currentContext!,
        builder: (c) => StatefulBuilder(
          builder: (c, update) => AlertDialog(
            title: const Text('Conectar um dispositivo'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Leia este QR no outro aparelho. Convite válido por 5 minutos e uma única tentativa.',
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
                          'Convite copiado. Compartilhe apenas com o outro aparelho.',
                        );
                      }),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar convite'),
                    ),
                    ExpansionTile(
                      title: const Text('Dados para conexão manual'),
                      children: [
                        SelectableText(
                          'IP: $host\nPorta: ${invite.port}\nCertificado SHA-256:\n${invite.fingerprint}\nCódigo secreto:\n${invite.secret}',
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
                child: const Text('Fechar e revogar convite'),
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
          title: const Text('Parear dispositivo'),
          content: SizedBox(
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Crie um convite no outro aparelho. Confirme o pareamento também na tela dele.',
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Informar IP e credenciais'),
                    value: manual,
                    onChanged: busy ? null : (v) => update(() => manual = v),
                  ),
                  if (!manual)
                    TextField(
                      controller: input,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Cole o convite OmniLink',
                      ),
                    ),
                  if (manual) ...[
                    TextField(
                      controller: ip,
                      decoration: const InputDecoration(
                        labelText: 'IPv4 local',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: portInput,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Porta'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fingerprint,
                      decoration: const InputDecoration(
                        labelText: 'Certificado SHA-256 do convite',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: secret,
                      decoration: const InputDecoration(
                        labelText: 'Código secreto do convite',
                      ),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!),
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
              child: const Text('Fechar'),
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
                        showMessage('Dispositivo pareado com segurança.');
                      } catch (e) {
                        if (c.mounted) {
                          update(() {
                            busy = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              child: const Text('Conectar'),
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
    showMessage('Dispositivo pareado com segurança.');
  }

  void infoDialog(Peer device) => showDialog<void>(
    context: navigator.currentContext!,
    builder: (c) => AlertDialog(
      title: Text(device.name),
      content: SingleChildScrollView(
        child: SelectableText(
          'Estado: ${device.status}\nIP: ${device.host}:${device.port}\nSistema: ${device.info['os'] ?? 'não disponível'}\nVersão: ${device.info['version'] ?? 'não disponível'}\nBateria: ${device.info['battery'] == null ? 'não disponível' : '${device.info['battery']}%'}\nEspaço livre: ${device.info['freeBytes'] == null ? 'não disponível' : '${(device.info['freeBytes'] / 1073741824).toStringAsFixed(1)} GiB'}\nÚltima conexão: ${device.lastSeen?.toLocal().toString() ?? 'não disponível'}\n\nCertificado SHA-256:\n${device.fingerprint}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Fechar'),
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
    appBar: AppBar(title: const Text('Ler convite OmniLink')),
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
