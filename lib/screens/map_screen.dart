import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Reemplaza con tu clave API de Geoapify
const String apiKey = 'e4c6ca4ce6a24ab49aa6ad071926c69d';

class Place {
  final String name;
  final String address;
  final List<String> categories;
  final double lat;
  final double lon;

  Place({
    required this.name,
    required this.address,
    required this.categories,
    required this.lat,
    required this.lon,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    final properties = json['properties'];
    final geometry = json['geometry']['coordinates'];
    return Place(
      name: properties['name'] ?? 'Desconocido',
      address: properties['address_line2'] ?? '',
      categories: List<String>.from(properties['categories'] ?? []),
      lon: geometry[0],
      lat: geometry[1],
    );
  }
}

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController mapController = MapController();
  Position? currentPosition;
  List<Place> places = [];
  bool isLoading = false;
  String? selectedCategory; // <-- Puede ser null al inicio

  // Lista de categorías y nombres para los botones
  final List<Map<String, String>> categories = [
    {'key': 'catering.restaurant', 'label': 'Restaurantes'},
    {'key': 'catering.cafe', 'label': 'Cafés'},
    {'key': 'healthcare.hospital', 'label': 'Hospitales'},
    {'key': 'tourism.attraction', 'label': 'Atracciones'},
    {'key': 'commercial.supermarket', 'label': 'Supermercados'},
    // Puedes agregar más de la documentación de Geoapify
  ];

  List<LatLng> routePoints = [];
  LatLng? selectedPoint;

  String mapStyle = 'osm-carto'; // Normal por defecto

  // 1. Agrega más estilos a tu mapa:
  final Map<String, String> mapStyles = {
    'OSM Carto': 'osm-carto',
    'OSM Bright': 'osm-bright',
    'OSM Bright Grey': 'osm-bright-grey',
    'OSM Bright Smooth': 'osm-bright-smooth',
    'Klokantech Basic': 'klokantech-basic',
    'OSM Liberty': 'osm-liberty',
    'Maptiler 3D': 'maptiler-3d',
    'Toner': 'toner',
    'Toner Grey': 'toner-grey',
    'Positron': 'positron',
    'Positron Blue': 'positron-blue',
    'Positron Red': 'positron-red',
    'Dark Matter': 'dark-matter',
    'Dark Matter Brown': 'dark-matter-brown',
    'Dark Matter Grey': 'dark-matter-dark-grey',
    'Dark Matter Purple': 'dark-matter-dark-purple',
    'Dark Matter Purple Roads': 'dark-matter-purple-roads',
    'Dark Matter Yellow Roads': 'dark-matter-yellow-roads',
  };

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('Activa los servicios de ubicación.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Permiso de ubicación denegado.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showError('Permiso denegado permanentemente.');
      return;
    }

    currentPosition = await Geolocator.getCurrentPosition();
    setState(() {});
  }

  // Cambia esta función para buscar cerca de la marca si existe, si no de la ubicación real
  Future<void> _searchPlacesByCategory(String category) async {
    if (selectedCategory == category) {
      setState(() {
        selectedCategory = null;
        places.clear();
      });
      return;
    }

    LatLng? searchPoint;
    if (selectedPoint != null) {
      searchPoint = selectedPoint;
    } else if (currentPosition != null) {
      searchPoint = LatLng(currentPosition!.latitude, currentPosition!.longitude);
    } else {
      _showError('No hay punto de búsqueda disponible.');
      return;
    }

    setState(() {
      isLoading = true;
      selectedCategory = category;
    });

    final url =
        'https://api.geoapify.com/v2/places?categories=$category'
        '&filter=circle:${searchPoint?.longitude},${searchPoint?.latitude},1000'
        '&limit=20'
        '&apiKey=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final features = data['features'] as List;
      setState(() {
        places = features.map((feature) => Place.fromJson(feature)).toList();
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
      _showError('Error al cargar los lugares.');
    }
  }

  Future<void> _getRouteToPlace(Place place) async {
    if (currentPosition == null) return;

    setState(() {
      routePoints = []; // Limpia la ruta anterior
    });

    final from = '${currentPosition!.latitude},${currentPosition!.longitude}';
    final to = '${place.lat},${place.lon}';
    final url =
        'https://api.geoapify.com/v1/routing?waypoints=$from|$to&mode=drive&format=geojson&apiKey=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final features = data['features'] as List;
      if (features.isNotEmpty) {
        final geometry = features[0]['geometry'];
        if (geometry['type'] == 'LineString') {
          setState(() {
            routePoints = (geometry['coordinates'] as List)
                .map<LatLng>((c) => LatLng(c[1], c[0]))
                .toList();
          });
        } else if (geometry['type'] == 'MultiLineString') {
          // Si la geometría es MultiLineString, concatena todos los puntos
          setState(() {
            routePoints = (geometry['coordinates'] as List)
                .expand((line) => (line as List)
                    .map<LatLng>((c) => LatLng(c[1], c[0])))
                .toList();
          });
        }
      }
    } else {
      _showError('No se pudo calcular la ruta.');
    }
  }

  Future<void> _searchPlacesNearPoint() async {
    if (selectedPoint == null || selectedCategory == null) return;
    setState(() { isLoading = true; });

    final url =
        'https://api.geoapify.com/v2/places?categories=$selectedCategory'
        '&filter=circle:${selectedPoint!.longitude},${selectedPoint!.latitude},1000'
        '&limit=20'
        '&apiKey=$apiKey';

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final features = data['features'] as List;
      setState(() {
        places = features.map((feature) => Place.fromJson(feature)).toList();
        isLoading = false;
      });
    } else {
      setState(() { isLoading = false; });
      _showError('Error al cargar los lugares.');
    }
  }

  void _showError(String message) {
    if (!mounted) return; // <- evita llamar si el widget no está montado
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  IconData getIconForCategory(String category) {
    if (category.contains('restaurant')) return Icons.restaurant;
    if (category.contains('cafe')) return Icons.local_cafe;
    if (category.contains('hospital')) return Icons.local_hospital;
    if (category.contains('attraction')) return Icons.camera_alt;
    if (category.contains('supermarket')) return Icons.shopping_cart;
    return Icons.location_on;
  }

  @override
  Widget build(BuildContext context) {
    if (currentPosition == null) {
      return Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: LatLng(currentPosition!.latitude, currentPosition!.longitude),
              initialZoom: 13.0,
              onTap: (tapPosition, point) {
                setState(() {
                  selectedPoint = point;
                  places.clear();
                  selectedCategory = null;
                  routePoints.clear();
                });
              },
            ),
            children: [
              TileLayer(
                // 3. Asegúrate de que tu TileLayer use la variable mapStyle:
                urlTemplate: 'https://maps.geoapify.com/v1/tile/$mapStyle/{z}/{x}/{y}.png?apiKey=$apiKey',
                userAgentPackageName: 'com.example.geoapify_app',
              ),
              MarkerLayer(
                markers: [
                  if (selectedPoint == null && currentPosition != null)
                    Marker(
                      point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
                      width: 60,
                      height: 60,
                      child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                    ),
                  if (selectedPoint != null)
                    Marker(
                      point: selectedPoint!,
                      width: 60,
                      height: 60,
                      child: Icon(Icons.place, color: Colors.green, size: 40),
                    ),
                  ...places.map((place) => Marker(
                    point: LatLng(place.lat, place.lon),
                    width: 80,
                    height: 80,
                    child: GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(place.name),
                            content: Text(place.address),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _getRouteToPlace(place);
                                },
                                child: Text('Cómo llegar'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Cerrar'),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Icon(getIconForCategory(selectedCategory ?? ''), color: Colors.red),
                    ),
                  )),
                ],
              ),
              PolylineLayer(
                polylines: routePoints.isNotEmpty
                    ? [
                        Polyline<Object>(
                          points: routePoints,
                          color: Colors.blue,
                          strokeWidth: 5,
                        ),
                      ]
                    : <Polyline<Object>>[],
              ),
            ],
          ),
          // Botones de categorías arriba
          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = selectedCategory == cat['key'];
                  IconData icon;
                  switch (cat['key']) {
                    case 'catering.restaurant':
                      icon = Icons.restaurant;
                      break;
                    case 'catering.cafe':
                      icon = Icons.local_cafe;
                      break;
                    case 'healthcare.hospital':
                      icon = Icons.local_hospital;
                      break;
                    case 'tourism.attraction':
                      icon = Icons.camera_alt;
                      break;
                    case 'commercial.supermarket':
                      icon = Icons.shopping_cart;
                      break;
                    default:
                      icon = Icons.place;
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ElevatedButton.icon(
                      icon: Icon(icon, color: isSelected ? Colors.white : Colors.blueGrey),
                      label: Text(
                        cat['label']!,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.blueGrey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.blue : Colors.white,
                        elevation: isSelected ? 6 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                          side: BorderSide(
                            color: isSelected ? Colors.blue : Colors.blueGrey,
                            width: 2,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onPressed: () => _searchPlacesByCategory(cat['key']!),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          if (isLoading)
            Center(child: CircularProgressIndicator()),
          // Menú de estilos de mapa abajo centrado
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: mapStyle,
                    items: mapStyles.entries.map((entry) {
                      return DropdownMenuItem(
                        value: entry.value,
                        child: Text(entry.key, style: TextStyle(fontSize: 15)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        mapStyle = value!;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedPoint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: FloatingActionButton(
                heroTag: 'clearSelection',
                backgroundColor: Colors.orange,
                onPressed: () {
                  setState(() {
                    selectedPoint = null;
                    places.clear();
                    selectedCategory = null;
                    routePoints.clear();
                  });
                },
                child: Icon(Icons.highlight_off),
                tooltip: 'Borrar selección',
              ),
            ),
          if (routePoints.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: FloatingActionButton(
                heroTag: 'clearRoute',
                backgroundColor: Colors.red,
                onPressed: () {
                  setState(() {
                    routePoints.clear();
                  });
                },
                child: Icon(Icons.clear),
                tooltip: 'Quitar ruta',
              ),
            ),
          FloatingActionButton(
            heroTag: 'myLocation',
            onPressed: () {
              if (currentPosition != null) {
                mapController.move(
                  LatLng(currentPosition!.latitude, currentPosition!.longitude),
                  13.0,
                );
              }
            },
            child: Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}