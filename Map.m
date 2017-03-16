classdef Map < handle
    properties (Access='private')
        urls = struct(...
            'osm', 'http://a.tile.openstreetmap.org', ...
            'hot', 'http://a.tile.openstreetmap.fr/hot', ...
            'ocm', 'http://a.tile.opencyclemap.org/cycle', ...
            'opm', 'http://www.openptmap.org/tiles', ...
            'landscape', 'http://a.tile.thunderforest.com/landscape', ...
            'outdoors', 'http://a.tile.thunderforest.com/outdoors');
        ax
        cache = struct('x', {}, 'y', {}, 'zoom', {}, ...
                       'style', {}, 'data', {});
    end

    properties
        coords = []
        style = []
    end

    properties (Dependent)
        zoomLevel
        styles
    end

    methods
        function obj = Map(ax, coords, style)
            obj.ax = ax;
            narginchk(1, 3);
            if nargin >= 2
                obj.coords = coords;
            end
            if nargin >= 3
                obj.style = style;
            else
                obj.style = 'osm';
            end
        end

        function redraw(obj)
            if isempty(obj.coords) || isempty(obj.style)
                return
            end

            if ~ishandle(obj.ax)
                error('can''t draw on closed axes');
            end

            [minX, maxX, minY, maxY] = obj.tileIndices();

            % set figure to the correct aspect ratio
            degHeight = (obj.coords.maxLat-obj.coords.minLat);
            degWidth = (obj.coords.maxLon-obj.coords.minLon);
            pixelTileWidth = 256*(maxX-minX+1); % 256 px per tile
            pixelTileHeight = 256*(maxY-minY+1); % 256 px per tile
            degTileWidth = abs(obj.x2lon(maxX+1) - ...
                               obj.x2lon(minX));
            degTileHeight = abs(obj.y2lat(maxY+1) - ...
                                obj.y2lat(minY));
            pixelWidth = pixelTileWidth/degTileWidth*degWidth;
            pixelHeight = pixelTileHeight/degTileHeight*degHeight;
            pbaspect(obj.ax, [pixelWidth/pixelHeight, 1, 1]);

            hold(obj.ax, 'on');
            axis(obj.ax, 'xy');
            xlim(obj.ax, [obj.coords.minLon, obj.coords.maxLon]);
            ylim(obj.ax, [obj.coords.minLat, obj.coords.maxLat]);

            % download tiles
            for x=(minX-1):(maxX+1)
                for y=(minY-1):(maxY+1)
                    imagedata = obj.searchCache(x, y);
                    if isempty(imagedata)
                        try
                            imagedata = obj.downloadTile(x, y);
                        catch
                            warning(['couldn''t download tile at ', ...
                                     obj.formatLatLon(obj.y2lat(y), ...
                                                      obj.x2lon(x))]);
                            continue
                        end
                    end
                    obj.cache = [obj.cache, ...
                                 struct('x', x, 'y', y, ...
                                        'zoom', obj.zoomLevel, ...
                                        'style', obj.style, ...
                                        'data', imagedata)];
                    image(obj.ax, ...
                          obj.x2lon([x, x+1]), ...
                          obj.y2lat([y, y+1]), ...
                          imagedata);
                    drawnow();
                end
            end
        end

        function zoom = get.zoomLevel(obj)
            % make sure we are at least 2 tiles high/wide
            latHeight = (obj.coords.maxLat-obj.coords.minLat);
            latZoom = ceil(log2(170.1022/latHeight));
            lonWidth = (obj.coords.maxLon-obj.coords.minLon);
            lonZoom = ceil(log2(360/lonWidth));
            zoom = min([lonZoom, latZoom])+1; % zoom in by 1
        end

        function set.coords(obj, coords)
            if ~isa(coords, 'struct') || ...
               ~all(isfield(coords, {'minLon', 'maxLon', 'minLat', 'maxLat'}))
                error(['coords must be a struct with fields ', ...
                       '''minLon'', ''maxLon'', ''minLat'', ', ...
                       'and ''maxLat'' in degrees']);
            end
            obj.coords = coords;
            obj.redraw();
        end

        function set.style(obj, style)
            if ~isfield(obj.urls, style)
                validFields = fieldnames(obj.urls);
                % format field names for listing them:
                validFields = cellfun(@(f)['''' f ''' '], validFields, ...
                                      'uniformoutput', false);
                error(['style must be one of ', ...
                       [validFields{:}]]);
            end
            obj.style = style;
            obj.redraw();
        end

        function styles = get.styles(obj)
            styles = fieldnames(obj.urls);
        end

        function [minX, maxX, minY, maxY] = tileIndices(obj)
            minX = obj.lon2x(obj.coords.minLon);
            maxX = obj.lon2x(obj.coords.maxLon);
            if minX > maxX
                [minX, maxX] = deal(maxX, minX);
            end

            minY = obj.lat2y(obj.coords.minLat);
            maxY = obj.lat2y(obj.coords.maxLat);
            if minY > maxY
                [minY, maxY] = deal(maxY, minY);
            end
        end

        function imagedata = downloadTile(obj, x, y)
            baseurl = obj.urls.(obj.style);
            url = sprintf('%s/%i/%d/%d.png', baseurl, obj.zoomLevel, x, y);
            [indices, cmap] = imread(url);
            imagedata = ind2rgb(indices, cmap);
        end

        function x = lon2x(obj, lon)
            x = floor(2^obj.zoomLevel * ((lon + 180) / 360));
        end

        function y = lat2y(obj, lat)
            lat = lat / 180 * pi;
            y = floor(2^obj.zoomLevel * (1 - (log(tan(lat) + sec(lat)) / pi)) / 2);
        end

        function lon = x2lon(obj, x)
            lon = x / 2^obj.zoomLevel * 360 - 180;
        end

        function lat = y2lat(obj, y)
            lat_rad = atan(sinh(pi * (1 - 2 * y / (2^obj.zoomLevel))));
            lat = lat_rad * 180 / pi;
        end

        function str = formatLatLon(obj, lat, lon)
            str = '';
            if lat > 0
                str = [str sprintf('%.3f N, ', lat)];
            else
                str = [str sprintf('%.3f S, ', -lat)];
            end
            if lon > 0
                str = [str sprintf('%.3f E', lon)];
            else
                str = [str sprintf('%.3f W', -lon)];
            end
        end

        function imagedata = searchCache(obj, x, y)
            imagedata = [];
            if isempty(obj.cache)
                return
            end
            zoom = obj.zoomLevel;
            style = obj.style;
            for entry=obj.cache
                if entry.x == x && entry.y == y && ...
                   entry.zoom == zoom && strcmp(entry.style, style)
                    imagedata = entry.data;
                    return
                end
            end
        end
    end

end
