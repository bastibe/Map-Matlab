classdef Mapper < handle
    properties
        urls = struct(...
            'osm', 'http://a.tile.openstreetmap.org', ...
            'hot', 'http://a.tile.openstreetmap.fr/hot', ...
            'ocm', 'http://a.tile.opencyclemap.org/cycle', ...
            'opm', 'http://www.openptmap.org/tiles', ...
            'landscape', 'http://a.tile.thunderforest.com/landscape', ...
            'outdoors', 'http://a.tile.thunderforest.com/outdoors');
        fig
        mapax
    end

    methods
        function obj = Mapper(place, style)
            obj.fig = [];
            obj.createGUI(place, style);
        end

	    function delete(obj)
	        close(obj.fig);
	    end

        function createGUI(obj, place, style)
            coords = obj.downloadCoords(place);
            zoom = obj.estimateZoomLevel(coords);
            [minX, maxX, minY, maxY] = obj.tileIndices(coords, zoom);

            % recreate figure if necessary:
            if isempty(obj.fig) | ~isvalid(obj.fig)
                obj.fig = figure();
                obj.mapax = axes(obj.fig);
                drawnow();
            end

            % set figure to the correct aspect ratio
            degHeight = (coords.maxLat-coords.minLat);
            degWidth = (coords.maxLon-coords.minLon);
            pixelTileWidth = 256*(maxX-minX+1); % 256 px per tile
            pixelTileHeight = 256*(maxY-minY+1); % 256 px per tile
            degTileWidth = abs(obj.x2lon(maxX+1, zoom)-obj.x2lon(minX, zoom));
            degTileHeight = abs(obj.y2lat(maxY+1, zoom)-obj.y2lat(minY, zoom));
            pixelWidth = pixelTileWidth/degTileWidth*degWidth;
            pixelHeight = pixelTileHeight/degTileHeight*degHeight;
            obj.fig.Position = [obj.fig.Position(1), ...
                                obj.fig.Position(2), ...
                                pixelWidth, ...
                                pixelHeight];

            hold('on');
            axis('xy');
            xlim([coords.minLon, coords.maxLon]);
            ylim([coords.minLat, coords.maxLat]);
            title(place);

            hpan = pan(obj.fig);
            hpan.ActionPostCallback = @(obj, event)disp(event.Axes);
            hpan.Enable = 'on';

            % download tiles
            for x=minX:maxX
                for y=minY:maxY
                    imagedata = obj.downloadTile(x, y, zoom, style);
                    image(obj.x2lon([x, x+1], zoom), ...
                          obj.y2lat([y, y+1], zoom), imagedata);
                    drawnow();
                end
            end
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

        function zoom = estimateZoomLevel(obj, coords)
            % make sure we are at least 4 tiles high/wide
            latHeight = (coords.maxLat-coords.minLat);
            latZoom = ceil(log2(170.1022/latHeight));
            lonWidth = (coords.maxLon-coords.minLon);
            lonZoom = ceil(log2(360/lonWidth));
            zoom = max([lonZoom, latZoom])+1; % zoom in by 1
        end

        function [minX, maxX, minY, maxY] = tileIndices(obj, coords, zoom)
            minX = obj.lon2x(coords.minLon, zoom);
            maxX = obj.lon2x(coords.maxLon, zoom);
            if minX > maxX
                [minX, maxX] = deal(maxX, minX);
            end

            minY = obj.lat2y(coords.minLat, zoom);
            maxY = obj.lat2y(coords.maxLat, zoom);
            if minY > maxY
                [minY, maxY] = deal(maxY, minY);
            end
        end

        function imagedata = downloadTile(obj, x, y, zoom, style)
            baseurl = obj.urls.(style);
            url = sprintf('%s/%i/%d/%d.png', baseurl, zoom, x, y);
            [indices, cmap] = imread(url);
            imagedata = ind2rgb(indices, cmap);
        end

        function x=lon2x(obj, lon, zoom)
            x = floor(2^zoom * ((lon + 180) / 360));
        end

        function y=lat2y(obj, lat, zoom)
            lat = lat / 180 * pi;
            y = floor(2^zoom * (1 - (log(tan(lat) + sec(lat)) / pi)) / 2);
        end

        function lon=x2lon(obj, x, zoom)
            lon = x / 2^zoom * 360 - 180;
        end

        function lat=y2lat(obj, y, zoom)
            lat_rad = atan(sinh(pi * (1 - 2 * y / (2^zoom))));
            lat = lat_rad * 180 / pi;
        end
    end

end
