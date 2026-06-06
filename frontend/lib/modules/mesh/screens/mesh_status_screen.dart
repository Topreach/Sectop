import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants.dart';
import '../../../core/themes.dart';
import '../services/mesh_manager.dart';

class MeshStatusScreen extends StatefulWidget {
  const MeshStatusScreen({Key? key}) : super(key: key);

  @override
  State<MeshStatusScreen> createState() => _MeshStatusScreenState();
}

class _MeshStatusScreenState extends State<MeshStatusScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MeshManager>().startScanning();
    });
  }

  @override
  Widget build(BuildContext context) {
    final meshManager = context.watch<MeshManager>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Network'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => meshManager.startScanning(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Network overview
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryColor.withOpacity(0.1),
            child: Row(
              children: [
                Expanded(
                  child: _NetworkStat(
                    icon: Icons.wifi_tethering,
                    label: 'Peers',
                    value: '${meshManager.discoveredPeers.length}',
                    color: meshManager.discoveredPeers.isNotEmpty ? Colors.green : Colors.grey,
                  ),
                ),
                Expanded(
                  child: _NetworkStat(
                    icon: Icons.bluetooth,
                    label: 'Bluetooth',
                    value: '${meshManager.discoveredPeers.where((p) => p.connectionType == ConnectionType.bluetooth).length}',
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _NetworkStat(
                    icon: Icons.wifi,
                    label: 'Wi-Fi Direct',
                    value: '${meshManager.discoveredPeers.where((p) => p.connectionType == ConnectionType.wifiDirect).length}',
                    color: Colors.purple,
                  ),
                ),
                Expanded(
                  child: _NetworkStat(
                    icon: Icons.satellite,
                    label: 'LoRa',
                    value: '${meshManager.discoveredPeers.where((p) => p.connectionType == ConnectionType.lora).length}',
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Scanning indicator
          if (meshManager.isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Scanning for nearby devices...'),
                ],
              ),
            ),

          // Peer list
          Expanded(
            child: meshManager.discoveredPeers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_tethering, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No peers found',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[500],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ensure Bluetooth and Wi-Fi are enabled',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: meshManager.discoveredPeers.length,
                    itemBuilder: (context, index) {
                      final peer = meshManager.discoveredPeers[index];
                      return _PeerCard(peer: peer);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _NetworkStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _NetworkStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}

class _PeerCard extends StatelessWidget {
  final MeshPeer peer;

  const _PeerCard({required this.peer});

  IconData _getConnectionIcon() {
    switch (peer.connectionType) {
      case ConnectionType.bluetooth:
        return Icons.bluetooth;
      case ConnectionType.wifiDirect:
        return Icons.wifi;
      case ConnectionType.lora:
        return Icons.satellite;
    }
  }

  Color _getSignalColor() {
    final strength = peer.signalStrength ?? 0;
    if (strength >= -50) return Colors.green;
    if (strength >= -70) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getSignalColor().withOpacity(0.2),
          child: Icon(
            _getConnectionIcon(),
            color: _getSignalColor(),
          ),
        ),
        title: Text(peer.name ?? peer.deviceId),
        subtitle: Text(
          '${peer.connectionType.name} | Signal: ${peer.signalStrength ?? 0} dBm${peer.isGateway ? ' | Gateway' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.signal_cellular_alt,
              color: _getSignalColor(),
            ),
            Text(
              '${peer.signalStrength ?? 0} dBm',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
