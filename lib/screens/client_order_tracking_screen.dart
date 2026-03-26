import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import '../core/supabase_service.dart';

class ClientOrderTrackingScreen extends StatefulWidget {
  final dynamic orderId;
  final String deliveryAddress;

  const ClientOrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.deliveryAddress,
  });

  @override
  State<ClientOrderTrackingScreen> createState() => _ClientOrderTrackingScreenState();
}

class _ClientOrderTrackingScreenState extends State<ClientOrderTrackingScreen> {
  GoogleMapController? _mapController;
  StreamSubscription? _orderSub;

  Map<String, dynamic>? _orderData;

  LatLng? _destinationLocation;
  LatLng? _courierLocation;

  bool _isLoading = true;

  // Початкова позиція (поки вантажиться)
  final CameraPosition _initialPosition = const CameraPosition(
    target: LatLng(48.4500, 27.7833), // Приблизно Могилів-Подільський
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    _initTracking();
  }

  Future<void> _initTracking() async {
    // 1. Шукаємо координати будинку клієнта (куди везти)
    try {
      // Додаємо Україну для точності
      List<Location> locations = await locationFromAddress('${widget.deliveryAddress}, Україна');
      if (locations.isNotEmpty) {
        _destinationLocation = LatLng(locations.first.latitude, locations.first.longitude);
      }
    } catch (e) {
      debugPrint('Не вдалося знайти координати адреси: $e');
    }

    // 2. Підписуємося на оновлення замовлення в реальному часі
    _orderSub = SupabaseService.client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', widget.orderId)
        .listen((List<Map<String, dynamic>> data) {
      if (data.isNotEmpty) {
        final order = data.first;
        if (mounted) {
          setState(() {
            _orderData = order;
            _isLoading = false;

            // Якщо кур'єр передав координати
            if (order['courier_lat'] != null && order['courier_lng'] != null) {
              _courierLocation = LatLng(order['courier_lat'], order['courier_lng']);

              // Центруємо камеру на кур'єрі
              if (_mapController != null) {
                _mapController!.animateCamera(
                  CameraUpdate.newLatLng(_courierLocation!),
                );
              }
            } else if (_destinationLocation != null && _courierLocation == null && _mapController != null) {
              // Якщо кур'єра ще немає, центруємо на будинку клієнта
              _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(_destinationLocation!, 15),
              );
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // Створюємо маркери для карти
  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = {};

    // Маркер будинку
    if (_destinationLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          infoWindow: const InfoWindow(title: 'Ваша адреса', snippet: 'Очікуємо доставку сюди'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }

    // Маркер кур'єра
    if (_courierLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('courier'),
          position: _courierLocation!,
          infoWindow: const InfoWindow(title: 'Кур\'єр', snippet: 'Вже в дорозі!'),
          // Робимо маркер кур'єра фіолетовим, щоб відрізнявся
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          zIndex: 2, // Щоб кур'єр був поверх будинку, якщо вони поруч
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // ДОЗВОЛЯЄ КАРТІ БУТИ ПІД APPBAR
      appBar: AppBar(
        title: Text('Замовлення #${widget.orderId.toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        backgroundColor: Colors.transparent, // ПРОЗОРИЙ APPBAR
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.7), Colors.transparent], // ГРАДІЄНТ ДЛЯ ЧИТАБЕЛЬНОСТІ
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack( // ВИКОРИСТОВУЄМО STACK, ЩОБ ПАНЕЛЬ ВИСІЛА НАД КАРТОЮ
        children: [
          // --- ШАР 1: КАРТА (на весь екран) ---
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: _initialPosition,
              markers: _buildMarkers(),
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false, // Ховаємо зайві кнопки гугла
              onMapCreated: (controller) {
                _mapController = controller;
                if (_courierLocation != null) {
                  controller.animateCamera(CameraUpdate.newLatLngZoom(_courierLocation!, 16));
                } else if (_destinationLocation != null) {
                  controller.animateCamera(CameraUpdate.newLatLngZoom(_destinationLocation!, 16));
                }
              },
            ),
          ),

          // --- ШАР 2: ПЛАВАЮЧА ПАНЕЛЬ СТАТУСУ ЗНИЗУ ---
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95), // Скляний ефект
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF005BBB).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _orderData?['status'] == 'В дорозі' ? Icons.moped : Icons.soup_kitchen,
                            size: 28,
                            color: const Color(0xFF005BBB),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Статус замовлення:', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                              Text(
                                _orderData?['status'] ?? 'Завантаження...',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Динамічний текст статусу
                    if (_orderData?['status'] == 'Готується')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange, size: 20),
                            SizedBox(width: 8),
                            Expanded(child: Text('Кур\'єр ще не забрав замовлення. Карта оновиться, щойно він вирушить!', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))),
                          ],
                        ),
                      )
                    else if (_orderData?['status'] == 'В дорозі')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: const Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.deepPurple, size: 20),
                            SizedBox(width: 8),
                            Expanded(child: Text('Кур\'єр прямує до вас! Слідкуйте за маркером на карті.', style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.bold, fontSize: 13))),
                          ],
                        ),
                      )
                    else if (_orderData?['status'] == 'Доставлено')
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Expanded(child: Text('Смачного! Замовлення доставлено.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14))),
                            ],
                          ),
                        ),

                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1),
                    ),

                    const Text('Адреса доставки:', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(widget.deliveryAddress, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}