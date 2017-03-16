classdef Mapper < handle
    properties (Access='private')
        fig
        map
    end

    properties
        place
    end

    methods
        function obj = Mapper(place)
            obj.fig = figure();
            obj.map = Map(axes(obj.fig));
            obj.place = place;
        end

        function delete(obj)
            close(obj.fig);
        end

        function set.place(obj, place)
            coords = obj.downloadCoords(place);
            obj.map.coords = coords;
            obj.place = place;
        end

        function coords = downloadCoords(obj, place)
            baseurl = 'https://maps.googleapis.com/maps/api/geocode/json';
            url = sprintf('%s?&address=%s', baseurl, place);
            data = jsondecode(urlread(url));
            geometry = data.results.geometry.bounds;
            coords = struct('minLon', geometry.southwest.lng, ...
                            'maxLon', geometry.northeast.lng, ...
                            'minLat', geometry.southwest.lat, ...
                            'maxLat', geometry.northeast.lat);
        end
    end
end
