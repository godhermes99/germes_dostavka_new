import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/supabase_service.dart';
import '../providers/cart_provider.dart';
import 'dart:convert';
import 'dart:async';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../core/secrets.dart';

import 'main_navigator.dart';

class CheckoutScreen extends StatefulWidget {
  final dynamic restaurantId;

  const CheckoutScreen({super.key, required this.restaurantId});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _addressController = TextEditingController();
  final _commentController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _restaurantCommentController = TextEditingController();

  bool _isForAnotherPerson = false;
  bool _isSurprise = false;
  bool _isLoading = false;

  String? _savedFullAddress;
  bool _useSavedAddress = true;
  bool _isLoadingData = true;

  String? _selectedCity;
  final List<String> _settlements = [
    'м. Могилів-Подільський',
    'с. Немія',
    'с. Бронниця',
    'с. Серебрія',
    'с. Юрківці',
    'с. Озаринці'
  ];

  int _personsCount = 1;
  bool _isAsap = true;
  DateTime? _selectedDateTime;

  double _basePrice = 40.0;
  double _pricePerKm = 10.0;
  double _deliveryPrice = 0.0;
  double _distanceKm = 0.0;
  Location? _restaurantLocation;
  Timer? _debounceTimer;

  bool _showAddressDetails = false;
  bool _showRestaurantComment = false;
  bool _showCourierComment = false;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _addressController.dispose();
    _commentController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _restaurantCommentController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    try {
      final settingsRes = await SupabaseService.client.from('settings').select().eq('id', 1).maybeSingle();
      if (settingsRes != null) {
        _basePrice = (settingsRes['base_price'] as num?)?.toDouble() ?? 40.0;
        _pricePerKm = (settingsRes['price_per_km'] as num?)?.toDouble() ?? 10.0;
      }

      final restRes = await SupabaseService.client.from('restaurants').select('address').eq('id', widget.restaurantId).single();
      final restAddress = restRes['address'];

      if (restAddress != null && restAddress.toString().isNotEmpty) {
        List<Location> locs = await locationFromAddress('$restAddress, Україна');
        if (locs.isNotEmpty) _restaurantLocation = locs.first;
      }
    } catch (e) {
      debugPrint('Помилка завантаження даних: $e');
    }

    await _fetchSavedAddress();
  }

  Future<void> _fetchSavedAddress() async {
    try {
      final user = SupabaseService.client.auth.currentUser;
      if (user != null) {
        final profile = await SupabaseService.client.from('profiles').select('city, address').eq('user_id', user.id).single();

        final fetchedCity = profile['city']?.toString().trim();
        final fetchedAddress = profile['address']?.toString().trim();

        if (fetchedAddress != null && fetchedAddress.isNotEmpty) {
          setState(() {
            if (fetchedCity != null && fetchedCity.isNotEmpty) {
              _savedFullAddress = '$fetchedCity, $fetchedAddress';
            } else {
              _savedFullAddress = fetchedAddress;
            }
            _useSavedAddress = true;
          });
          await _calculateDeliveryPrice(_savedFullAddress!);
        } else {
          setState(() {
            _useSavedAddress = false;
            _deliveryPrice = _basePrice;
          });
        }
      }
    } catch (e) {
      setState(() {
        _useSavedAddress = false;
        _deliveryPrice = _basePrice;
      });
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  Future<void> _calculateDeliveryPrice(String clientAddress) async {
    if (clientAddress.trim().isEmpty) {
      setState(() {
        _distanceKm = 0.0;
        _deliveryPrice = _basePrice;
      });
      return;
    }

    try {
      List<Location> clientLocs = await locationFromAddress('$clientAddress, Україна');

      if (clientLocs.isNotEmpty && _restaurantLocation != null) {
        final double restLat = _restaurantLocation!.latitude;
        final double restLng = _restaurantLocation!.longitude;
        final double clientLat = clientLocs.first.latitude;
        final double clientLng = clientLocs.first.longitude;

        final String googleApiKey = AppSecrets.googleMapsKey;
        final String url = 'https://maps.googleapis.com/maps/api/directions/json?origin=$restLat,$restLng&destination=$clientLat,$clientLng&key=$googleApiKey';

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);

          if (data['status'] == 'OK') {
            final int distMeters = data['routes'][0]['legs'][0]['distance']['value'];
            double distKm = distMeters / 1000.0;

            if (mounted) {
              setState(() {
                _distanceKm = distKm;
                _deliveryPrice = _basePrice + (_pricePerKm * distKm);
              });
            }
          } else {
            _fallbackToStraightLineDistance(restLat, restLng, clientLat, clientLng);
          }
        } else {
          _fallbackToStraightLineDistance(restLat, restLng, clientLat, clientLng);
        }
      } else {
        if (mounted) setState(() => _deliveryPrice = _basePrice);
      }
    } catch (e) {
      if (mounted) setState(() => _deliveryPrice = _basePrice);
    }
  }

  void _fallbackToStraightLineDistance(double lat1, double lon1, double lat2, double lon2) {
    double distMeters = Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
    double distKm = distMeters / 1000.0;

    if (mounted) {
      setState(() {
        _distanceKm = distKm;
        _deliveryPrice = _basePrice + (_pricePerKm * distKm);
      });
    }
  }

  void _onAddressInputChanged(String val) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1500), () {
      if (_selectedCity != null && val.isNotEmpty) {
        _calculateDeliveryPrice('$_selectedCity, $val');
      }
    });
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final initialDate = _selectedDateTime ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF005BBB))), child: child!);
      },
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (context, child) {
        return Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFF005BBB))), child: child!);
      },
    );
    if (pickedTime == null) return;

    final finalDateTime = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);

    if (finalDateTime.isBefore(now)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Неможливо обрати час у минулому! ⏰')));
      return;
    }

    setState(() {
      _selectedDateTime = finalDateTime;
      _isAsap = false;
    });
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} о ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _placeOrder(CartProvider cart) async {
    String? finalAddress;
    String? finalCityToSave;

    if (_useSavedAddress) {
      finalAddress = _savedFullAddress;
      if (finalAddress == null || finalAddress.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Збережена адреса порожня. Оберіть нову.')));
        return;
      }
    } else {
      if (_selectedCity == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Оберіть населений пункт зі списку 🏘️')));
        return;
      }
      final street = _addressController.text.trim();
      if (street.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введіть вулицю та номер будинку 🏠')));
        return;
      }
      finalAddress = '$_selectedCity, $street';
      finalCityToSave = _selectedCity;
    }

    if (!_isAsap && _selectedDateTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Будь ласка, оберіть час або натисніть "Якнайшвидше"')));
      return;
    }

    if (_isForAnotherPerson && (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введіть ім\'я та телефон одержувача')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = SupabaseService.client.auth.currentUser;
      final totalWithDelivery = cart.total + _deliveryPrice;

      String? finalName = _nameController.text.trim();
      String? finalPhone = _phoneController.text.trim();

      if (!_isForAnotherPerson && user != null) {
        finalPhone = user.phone ?? 'Не вказано';
        try {
          final profile = await SupabaseService.client.from('profiles').select('full_name').eq('user_id', user.id).single();
          finalName = profile['full_name'] ?? 'Клієнт';
        } catch (e) {
          finalName = 'Клієнт';
        }
      }

      if (!_useSavedAddress && user != null) {
        try {
          await SupabaseService.client.from('profiles').update({'city': finalCityToSave, 'address': _addressController.text.trim()}).eq('user_id', user.id);
        } catch (e) {
          debugPrint('Не вдалося зберегти нову адресі в профіль: $e');
        }
      }

      final cartItemsForDb = cart.items.map((item) {
        return {
          'id': item['id'],
          'name': item['name'],
          'price': item['price'],
          'quantity': item['quantity'],
          'removed_ingredients': item['removed_ingredients'] ?? [],
          'added_ingredients': item['added_ingredients'] ?? [],
        };
      }).toList();

      final orderData = {
        'user_id': user?.id,
        'restaurant_id': widget.restaurantId,
        'total_amount': totalWithDelivery,
        'delivery_price': _deliveryPrice,
        'status': 'Очікує підтвердження',
        'delivery_address': finalAddress,
        'delivery_comment': _commentController.text.trim(),
        'is_for_another_person': _isForAnotherPerson,
        'receiver_name': finalName,
        'receiver_phone': finalPhone,
        'is_surprise': _isForAnotherPerson ? _isSurprise : false,
        'persons_count': _personsCount,
        'restaurant_comment': _restaurantCommentController.text.trim(),
        'desired_delivery_time': _isAsap ? null : _selectedDateTime?.toUtc().toIso8601String(),
        'items': cartItemsForDb,
      };

      final orderResponse = await SupabaseService.client.from('orders').insert(orderData).select().single();
      final orderId = orderResponse['id'];

      final itemsData = cart.items.map((item) => {
        'order_id': orderId,
        'dish_id': item['id'],
        'dish_name': item['name'],
        'price': item['price'],
        'quantity': item['quantity'],
        'removed_ingredients': jsonEncode(item['removed_ingredients'] ?? []),
        'added_ingredients': jsonEncode(item['added_ingredients'] ?? []),
      }).toList();

      await SupabaseService.client.from('order_items').insert(itemsData);

      if (mounted) {
        Provider.of<CartProvider>(context, listen: false).clear();
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainNavigator(initialIndex: 2)), // 2 - Історія
              (route) => false,
        );
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.black.withOpacity(0.6) : Colors.white.withOpacity(0.9);
    final inputBgColor = isDark ? Colors.black.withOpacity(0.4) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white54 : Colors.black54;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.grey[300]!;

    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Оформлення', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        centerTitle: false,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.only(
            left: 16, right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16, top: 16
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Вартість замовлення:', style: TextStyle(color: hintColor, fontSize: 14)),
                Text('${cart.total.toStringAsFixed(0)} ₴', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_distanceKm > 0 ? 'Доставка (${_distanceKm.toStringAsFixed(1)} км):' : 'Доставка:', style: TextStyle(color: hintColor, fontSize: 14)),
                Text('${_deliveryPrice.toStringAsFixed(0)} ₴', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFCD00),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                onPressed: _isLoading ? null : () => _placeOrder(cart),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.black)
                    : const Text('Замовити', style: TextStyle(fontSize: 18, color: Colors.black, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/images/bg.jpg'), fit: BoxFit.cover),
        ),
        child: Container(
          color: Colors.black.withOpacity(0.4),
          child: _isLoadingData
              ? const Center(child: CircularProgressIndicator())
              : ListView(
            padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight + 10, left: 16, right: 16, bottom: 20),
            children: [
              // ==========================================
              // 1. БЛОК АДРЕСИ
              // ==========================================
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => setState(() => _showAddressDetails = !_showAddressDetails),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Куди веземо?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                                if (!_showAddressDetails) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _useSavedAddress
                                        ? (_savedFullAddress ?? 'Натисніть, щоб обрати адресу')
                                        : (_selectedCity != null && _addressController.text.isNotEmpty
                                        ? '$_selectedCity, ${_addressController.text}'
                                        : 'Натисніть, щоб вказати адресу'),
                                    style: TextStyle(
                                      color: (_useSavedAddress && _savedFullAddress != null) || (!_useSavedAddress && _selectedCity != null && _addressController.text.isNotEmpty)
                                          ? const Color(0xFF005BBB)
                                          : Colors.redAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(_showAddressDetails ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: textColor),
                        ],
                      ),
                    ),

                    if (_showAddressDetails) ...[
                      const SizedBox(height: 16),
                      if (_savedFullAddress != null) ...[
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _useSavedAddress = true;
                              _showAddressDetails = false;
                            });
                            _calculateDeliveryPrice(_savedFullAddress!);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: _useSavedAddress ? const Color(0xFF005BBB).withOpacity(isDark ? 0.2 : 0.1) : Colors.transparent,
                              border: Border.all(color: _useSavedAddress ? const Color(0xFF005BBB) : borderColor, width: _useSavedAddress ? 2 : 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_rounded, color: _useSavedAddress ? const Color(0xFF005BBB) : hintColor, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('Моя адреса', style: TextStyle(fontWeight: _useSavedAddress ? FontWeight.bold : FontWeight.normal, color: textColor)),
                                ),
                                if (_useSavedAddress) const Icon(Icons.check_circle_rounded, color: Color(0xFF005BBB), size: 20),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        GestureDetector(
                          onTap: () {
                            setState(() => _useSavedAddress = false);
                            if (_selectedCity != null && _addressController.text.isNotEmpty) {
                              _calculateDeliveryPrice('$_selectedCity, ${_addressController.text}');
                            } else {
                              setState(() => _deliveryPrice = _basePrice);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: !_useSavedAddress ? const Color(0xFF005BBB).withOpacity(isDark ? 0.2 : 0.1) : Colors.transparent,
                              border: Border.all(color: !_useSavedAddress ? const Color(0xFF005BBB) : borderColor, width: !_useSavedAddress ? 2 : 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.add_location_alt_rounded, color: !_useSavedAddress ? const Color(0xFF005BBB) : hintColor, size: 20),
                                const SizedBox(width: 12),
                                Text('Інша адреса', style: TextStyle(color: textColor, fontWeight: !_useSavedAddress ? FontWeight.bold : FontWeight.normal)),
                              ],
                            ),
                          ),
                        ),
                        if (!_useSavedAddress) const SizedBox(height: 16),
                      ],

                      if (!_useSavedAddress) ...[
                        DropdownButtonFormField<String>(
                          value: _selectedCity,
                          dropdownColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            labelText: 'Населений пункт*',
                            labelStyle: TextStyle(color: hintColor),
                            filled: true,
                            fillColor: inputBgColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                            prefixIcon: const Icon(Icons.location_city_rounded, color: Color(0xFF005BBB)),
                          ),
                          items: _settlements.map((city) {
                            return DropdownMenuItem(value: city, child: Text(city, style: const TextStyle(fontWeight: FontWeight.w500)));
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedCity = value);
                            if (_addressController.text.isNotEmpty) {
                              _calculateDeliveryPrice('$_selectedCity, ${_addressController.text}');
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _addressController,
                          onChanged: _onAddressInputChanged,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            labelText: 'Вулиця, будинок, квартира*',
                            labelStyle: TextStyle(color: hintColor),
                            filled: true,
                            fillColor: inputBgColor,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                            prefixIcon: const Icon(Icons.home_rounded, color: Color(0xFF005BBB)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 🔥 ВИПРАВЛЕНО: Тепер ця кнопка ТІЛЬКИ ховає меню адреси, нічого не відправляючи!
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF005BBB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.check_rounded, size: 20),
                            onPressed: () {
                              if (_selectedCity == null || _addressController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введіть повну адресу!')));
                                return;
                              }
                              setState(() => _showAddressDetails = false);
                            },
                            label: const Text('Зберегти адресу', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),

              // ==========================================
              // 2. БЛОК ЧАСУ
              // ==========================================
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Коли доставити?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: _isAsap ? const Color(0xFF005BBB).withOpacity(0.1) : Colors.transparent,
                                side: BorderSide(color: _isAsap ? const Color(0xFF005BBB) : borderColor, width: _isAsap ? 2 : 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            onPressed: () => setState(() => _isAsap = true),
                            child: Text('Якнайшвидше', style: TextStyle(fontSize: 14, color: _isAsap ? const Color(0xFF005BBB) : textColor, fontWeight: _isAsap ? FontWeight.bold : FontWeight.normal)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: !_isAsap ? Colors.purple.withOpacity(0.1) : Colors.transparent,
                                side: BorderSide(color: !_isAsap ? Colors.purple : borderColor, width: !_isAsap ? 2 : 1),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            onPressed: _pickDateTime,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!_isAsap && _selectedDateTime != null) ...[
                                  Expanded(child: Text(_formatDateTime(_selectedDateTime!), style: TextStyle(fontSize: 14, color: Colors.purple, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ] else ...[
                                  Icon(Icons.schedule_rounded, size: 18, color: textColor),
                                  const SizedBox(width: 4),
                                  Text('Обрати час', style: TextStyle(fontSize: 14, color: textColor)),
                                ]
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ==========================================
              // 3. БЛОК ДЕТАЛЕЙ ТА КОМЕНТАРІВ
              // ==========================================
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.restaurant_rounded, color: Color(0xFF005BBB), size: 20),
                            const SizedBox(width: 8),
                            Text('Скільки персон?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline_rounded, color: textColor),
                              onPressed: () {
                                if (_personsCount > 1) setState(() => _personsCount--);
                              },
                            ),
                            SizedBox(width: 24, child: Text('$_personsCount', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor))),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF005BBB)),
                              onPressed: () {
                                if (_personsCount < 20) setState(() => _personsCount++);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: borderColor)),

                    InkWell(
                      onTap: () => setState(() => _showRestaurantComment = !_showRestaurantComment),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(_showRestaurantComment ? Icons.remove_rounded : Icons.add_rounded, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Text('Додати коментар для закладу', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    if (_showRestaurantComment) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _restaurantCommentController,
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Наприклад: без цибулі, поменше солі',
                          hintStyle: TextStyle(color: hintColor),
                          filled: true, fillColor: inputBgColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                        ),
                      ),
                    ],

                    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: borderColor)),

                    InkWell(
                      onTap: () => setState(() => _showCourierComment = !_showCourierComment),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(_showCourierComment ? Icons.remove_rounded : Icons.add_rounded, color: const Color(0xFF005BBB), size: 20),
                            const SizedBox(width: 8),
                            Text('Додати коментар для кур\'єра', style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    if (_showCourierComment) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _commentController,
                        style: TextStyle(color: textColor),
                        decoration: InputDecoration(
                          hintText: 'Наприклад: код домофону, залишити біля дверей',
                          hintStyle: TextStyle(color: hintColor),
                          filled: true, fillColor: inputBgColor,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ==========================================
              // 4. БЛОК "ДЛЯ ІНШОГО"
              // ==========================================
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8), width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Хто отримає замовлення?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(color: inputBgColor, border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(12)),
                      child: SwitchListTile(
                        title: Text('Замовляю для іншої людини', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
                        value: _isForAnotherPerson,
                        activeColor: const Color(0xFF005BBB),
                        onChanged: (val) => setState(() => _isForAnotherPerson = val),
                      ),
                    ),
                    if (_isForAnotherPerson) ...[
                      const SizedBox(height: 16),
                      TextField(
                          controller: _nameController,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(labelText: 'Ім\'я одержувача', labelStyle: TextStyle(color: hintColor), filled: true, fillColor: inputBgColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)), prefixIcon: const Icon(Icons.person_rounded))
                      ),
                      const SizedBox(height: 12),
                      TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(labelText: 'Телефон одержувача', labelStyle: TextStyle(color: hintColor), filled: true, fillColor: inputBgColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: borderColor)), prefixIcon: const Icon(Icons.phone_rounded))
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(color: isDark ? Colors.pink.withOpacity(0.1) : Colors.pink[50], border: Border.all(color: Colors.pink[200]!), borderRadius: BorderRadius.circular(12)),
                        child: SwitchListTile(
                          title: Text('Це сюрприз! 🎁', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                          subtitle: Text('Кур\'єр не скаже, що саме везе', style: TextStyle(fontSize: 12, color: hintColor)),
                          value: _isSurprise,
                          activeColor: Colors.pink,
                          onChanged: (val) => setState(() => _isSurprise = val),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}