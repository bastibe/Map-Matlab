classdef Map < handle
    properties (Hidden)
        urls = struct(...
            'osm', 'http://a.tile.openstreetmap.org', ...
            'hot', 'http://a.tile.openstreetmap.fr/hot', ...
            'ocm', 'http://a.tile.opencyclemap.org/cycle', ...
            'opm', 'http://www.openptmap.org/tiles', ...
            'landscape', 'http://a.tile.thunderforest.com/landscape', ...
            'outdoors', 'http://a.tile.thunderforest.com/outdoors');
    end

    properties
        style = []
        ax
    end

    properties (Dependent)
        zoomLevel
        styles
        coords
    end

    methods
        function obj = Map(ax, coords, style)
            obj.ax = ax;
            % schedule redraw and tile download when axis limits change:
            addlistener(obj.ax, 'YLim', 'PostSet', @(~, ~)obj.asyncRedraw);
            % to avoid redrawing on both XLim and YLim changes, we only
            % look for the latter, assuming that XLim-only changes are
            % rare for maps.
            narginchk(1, 3);
            if nargin >= 2
                obj.coords = coords;
            end
            if nargin >= 3
                obj.style = style;
            else
                obj.style = 'osm';
            end
            obj.ax.NextPlot = 'add';
            % add invisible markers at the coordinate system edges to allow
            % infinite panning. Otherwise, panning is restricted to drawn-in
            % areas.
            h = scatter(obj.ax, [-180, 180], [-90, 90]);
            h.MarkerEdgeAlpha = 0; % invisible
            h.MarkerFaceAlpha = 0; % invisible
        end

        function asyncRedraw(obj)
            % This is called every time the axis limits change, i.e. on every
            % pan or zoom. To avoid stuttering, do all downloading and
            % redrawing asynchronously:

            % only the latest redraw needs to survive:
            timers = timerfindall('Tag', 'redraw');
            if ~isempty(timers)
                stop(timers)
            end

            t = timer();
            function timerCallback(~, ~)
                obj.redraw();
            end
            t.TimerFcn = @timerCallback;
            t.BusyMode = 'queue';
            % make sure the timer doesn't stay around when it's done:
            t.StopFcn = @(~,~)delete(t);
            % set a short delay, otherwise start(t) blocks:
            t.StartDelay = 0.1;
            t.Tag = 'redraw';
            start(t);
        end

        function redraw(obj)
            if isempty(obj.style)
                return
            end

            if ~ishandle(obj.ax)
                error('can''t draw on closed axes');
            end

            [minX, maxX, minY, maxY] = obj.tileIndices();

            aspectRatio = diff(obj.ax.XLim)/diff(obj.ax.YLim);
            % correct skewing due to mercator projection:
            % (http://wiki.openstreetmap.org/wiki/ ...
            %  Slippy_map_tilenames#Resolution_and_Scale)
            mercatorCorrection = cos(mean(obj.ax.YLim)/180*pi);
            obj.ax.PlotBoxAspectRatio = [mercatorCorrection*aspectRatio, 1, 1];

            % bring current images to the top
            function yesNo = isCurrent(tile)
                yesNo = tile.UserData.zoom == obj.zoomLevel && ...
                        strcmp(tile.UserData.style, obj.style);
            end
            tiles = findobj(obj.ax.Children, 'Tag', 'maptile');
            if ~isempty(tiles)
                currentTiles = tiles(arrayfun(@isCurrent, tiles));
                if ~isempty(currentTiles)
                    uistack(currentTiles, 'top');
                end
            end

            % download tiles
            for x=max(0, (minX-1)):min((maxX+1), 2^obj.zoomLevel)
                for y=max(0, (minY-1)):min((maxY+1), 2^obj.zoomLevel)
                    % skip impossible tiles
                    if x < 0 || x > (2^obj.zoomLevel - 1) || ...
                       y < 0 || y > (2^obj.zoomLevel - 1)
                        continue
                    end

                    im = obj.searchCache(x, y);
                    if isempty(im)
                        try
                            imagedata = obj.downloadTile(x, y);
                        catch
                            warning(['couldn''t download tile at ', ...
                                     obj.formatLatLon(obj.y2lat(y), ...
                                                      obj.x2lon(x)), ...
                                     sprintf(' (zoom level %i)', ...
                                             obj.zoomLevel)]);
                            continue
                        end
                        im = image(obj.ax, ...
                                   obj.x2lon([x, x+1]), ...
                                   obj.y2lat([y, y+1]), ...
                                   imagedata);
                        im.UserData = struct('x', x, 'y', y, ...
                                             'zoom', obj.zoomLevel, ...
                                             'style', obj.style);
                        im.Tag = 'maptile';
                        % skip drawing updated invisible tiles
                        if x >= minX && x <= maxX && y >= minY && y <= maxY
                            drawnow();
                        end
                    end
                end
            end
            drawnow();
        end

        function coords = get.coords(obj)
            coords = struct('minLon', obj.ax.XLim(1), ...
                            'maxLon', obj.ax.XLim(2), ...
                            'minLat', obj.ax.YLim(1), ...
                            'maxLat', obj.ax.YLim(2));
        end

        function set.coords(obj, coords)
            obj.ax.XLim = [coords.minLon, coords.maxLon];
            obj.ax.YLim = [coords.minLat, coords.maxLat];
        end

        function zoom = get.zoomLevel(obj)
            % make sure we are at least 2 tiles high/wide
            latHeight = diff(obj.ax.YLim);
            latZoom = ceil(log2(170.1022/latHeight));
            lonWidth = diff(obj.ax.XLim);
            lonZoom = ceil(log2(360/lonWidth));
            zoom = min([lonZoom, latZoom])+1; % zoom in by 1
            zoom = min([zoom, 18]);
            zoom = max([0, zoom]);
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
            obj.asyncRedraw();
        end

        function styles = get.styles(obj)
            styles = fieldnames(obj.urls);
        end

        function [minX, maxX, minY, maxY] = tileIndices(obj)
            minX = obj.lon2x(obj.ax.XLim(1));
            maxX = obj.lon2x(obj.ax.XLim(2));
            if minX > maxX
                [minX, maxX] = deal(maxX, minX);
            end

            minY = obj.lat2y(obj.ax.YLim(1));
            maxY = obj.lat2y(obj.ax.YLim(2));
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

        function im = searchCache(obj, x, y)
            im = [];
            tiles = findobj(obj.ax.Children, 'Tag', 'maptile');
            if isempty(tiles)
                return
            end
            zoom = obj.zoomLevel;
            style = obj.style;
            for idx=1:length(tiles)
                entry = tiles(idx);
                if entry.UserData.x == x && entry.UserData.y == y && ...
                   entry.UserData.zoom == zoom && ...
                   strcmp(entry.UserData.style, style)
                    im = entry;
                    return
                end
            end
        end
    end

end
