'use client';

import 'maplibre-gl/dist/maplibre-gl.css';
import { Map, Marker, NavigationControl } from '@vis.gl/react-maplibre';
import { MAP_STYLE, SalonPin } from '../map/salon-pin';

/// The salon page's Localisation map (docs/design/web-m8-2-provider.md,
/// upgraded with #201's renderer): the same MapLibre + Positron + salon-pin
/// identity as /recherche, centered on the salon. Cooperative gestures so
/// page scrolling never gets trapped by the embed.
export function SalonLocationMap({
  name,
  category,
  latitude,
  longitude,
}: {
  name: string;
  category: string | undefined;
  latitude: number;
  longitude: number;
}) {
  return (
    <Map
      initialViewState={{ longitude, latitude, zoom: 15 }}
      mapStyle={MAP_STYLE}
      cooperativeGestures
      style={{ width: '100%', height: '100%' }}
    >
      <NavigationControl position="top-left" showCompass={false} />
      <Marker longitude={longitude} latitude={latitude} anchor="center">
        <SalonPin category={category} active={false} name={name} />
      </Marker>
    </Map>
  );
}
