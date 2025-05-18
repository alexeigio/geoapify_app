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

  Future<void> _handleTap(LatLng point) async {
    setState(() {
      isLoading = true;
    });

    // Cambia la categoría aquí, por ejemplo: catering.restaurant para restaurantes
    final url =
        'https://api.geoapify.com/v2/places?categories=catering.restaurant'
        '&filter=circle:${point.longitude},${point.latitude},1000'
        '&bias=proximity:${point.longitude},${point.latitude}'
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
              onTap: (tapPosition, point) => _handleTap(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=$apiKey',
                userAgentPackageName: 'com.example.geoapify_app',
              ),
              MarkerLayer(
                markers: [
                  // Marcador de tu ubicación
                  Marker(
                    point: LatLng(currentPosition!.latitude, currentPosition!.longitude),
                    width: 60,
                    height: 60,
                    child: Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                  ),
                  // Marcadores de lugares
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
                          ),
                        );
                      },
                      child: Icon(Icons.location_on, color: Colors.red),
                    ),
                  )),
                ],
              ),
            ],
          ),
          if (isLoading)
            Center(child: CircularProgressIndicator()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
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
    );
  }
}