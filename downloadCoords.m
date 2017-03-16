function coords = downloadCoords(place)
    baseurl = 'https://maps.googleapis.com/maps/api/geocode/json';
    url = sprintf('%s?&address=%s', baseurl, place);
    data = jsondecode(urlread(url));
    geometry = data.results.geometry.bounds;
    coords = struct('minLon', geometry.southwest.lng, ...
                    'maxLon', geometry.northeast.lng, ...
                    'minLat', geometry.southwest.lat, ...
                    'maxLat', geometry.northeast.lat);
end
