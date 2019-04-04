classdef Map < handle
%MAP draws a map on an axes
%   The map consists of tiles downloaded from openstreetmap. Whenever
%   the axes limits are changed (pan/zoom), or coords is updated, new map
%   tiles are downloaded as appropriate. Map tiles are cached, and are
%   never re-downloaded.
%
%   The map will make sure that map tiles are always drawn at the bottom
%   of the draw stack, so that users can draw their own things on top of
%   the map.
%
%   All map drawing is done asynchronously, so user interaction with a
%   GUI is interrupted as little as possible in Matlab by tile downloads.
%
%   MAP() draws a map into GCA using the axes XLim and YLim as
%   latitude and longitude.
%
%   MAP(COORDS) draws a map into GCA of some latitude/longitude
%   coordinates, either
%   - as an array: [minLon, maxLon, minLat, maxLat], or
%   - as a struct: struct("minLon", minLon, "maxLon", maxLon, ...
%                         "minLat", minLat, "maxLat", maxLat).
%
%   MAP(COORDS, STYLE) draws a map into GCA with a given style, which
%   can be:
%   - "osm" for OpenStreetMap's default look
%   - "hot" for humanitarian focused OSM base layer
%   - "ocm" for OpenCycleMap
%   - "opm" for public transport map
%   - "landscape" for Thunderforest landscape map
%   - "outdoors" for Thunderforest outdoors map
%   (from: http://wiki.openstreetmap.org/wiki/Tiles)
%
%   MAP(COORDS, STYLE, AX) draws the map int a given axes AX.
%
%   MAP(COORDS, STYLE, AX, BASEZOOM) changes tile resolution by a zoom
%   factor. By default (BASEZOOM=0), tiles use the native screen
%   resolution. However, big axes might require many tiles to download,
%   which can take a long time. To lower resolution, use BASEZOOM=-1 or
%   less. To increase resolution, use positive BASEZOOMs.
%
%   Example:
%      Map() % draws a map of the world
%      coords = [8.0 8.4 53.05 53.25]; % coordinates for Oldenburg
%      Map(coords);             % draws a map of Oldenburg
%      Map(coords, "ocm")       % draws a map for cycling
%      Map(coords, [], [], -2); % draws a low-res map

% Copyright (c) 2017, Bastian Bechtold
% This code is released under the terms of the BSD 3-clause license

    properties (Hidden)
        % a list of OSM map servers where we can download tiles from:
        urls = struct(...
            "osm", "http://a.tile.openstreetmap.org", ...
            "hot", "http://a.tile.openstreetmap.fr/hot", ...
            "ocm", "http://a.tile.opencyclemap.org/cycle", ...
            "opm", "http://www.openptmap.org/tiles", ...
            "landscape", "http://a.tile.thunderforest.com/landscape", ...
            "outdoors", "http://a.tile.thunderforest.com/outdoors");
    end

    properties
        style = []     % one style from possibleStyles
        ax             % the axes to draw on
        baseZoom       % base zoom modifier
    end

    properties (Dependent, SetAccess=private)
        zoomLevel      % the current zoom level (depending on coords)
        possibleStyles % a list of all possible styles
    end

    properties (Dependent)
        coords         % the latitude/longitude coordinates to display.
                       % This is a struct with keys "minLon", "maxLon",
                       % "minLat", "maxLat" in degrees.
    end

    methods
        function obj = Map(coords, style, ax, baseZoom)
        %MAP creates a Map on an axes with a certain style at coordinates
        %   This will download map tiles from the internet.

            if ~exist("ax") || isempty(ax)
                obj.ax = gca();
            else
                obj.ax = ax;
            end
            obj.ax.NextPlot = "add";

            % add invisible markers at the coordinate system edges to allow
            % infinite panning. Otherwise, panning is restricted to drawn-in
            % areas.
            h = scatter(obj.ax, [-180, 180], [-90, 90]);
            h.MarkerEdgeAlpha = 0; % invisible
            h.MarkerFaceAlpha = 0; % invisible

            % schedule redraw and tile download when axis limits change:
            addlistener(obj.ax, "YLim", "PostSet", @(~, ~)obj.asyncRedraw);
            % to avoid redrawing on both XLim and YLim changes, we only
            % look for the latter, assuming that XLim-only changes are
            % rare for maps.

            if ~exist("coords") || isempty(coords)
                % get coords from axes limits:
                obj.coords = struct(...
                    "minLon", obj.ax.XLim(1), "maxLon", obj.ax.XLim(2), ...
                    "minLat", obj.ax.YLim(1), "maxLat", obj.ax.YLim(2));
            elseif isa(coords, "double") && length(coords) == 4
                % coords are double array:
                obj.coords = struct(...
                    "minLon", coords(1), "maxLon", coords(2), ...
                    "minLat", coords(3), "maxLat", coords(4));
            elseif isa(coords, "struct") && all(sort(string(fieldnames(coords))) == ...
                                                ["maxLat"; "maxLon"; "minLat"; "minLon"])
                % coords are struct:
                obj.coords = coords;
            else
                error("coords are not supported");
            end

            if ~exist("style") || isempty(style)
                obj.style = "osm";
            elseif any(style == string(fieldnames(obj.urls)))
                obj.style = style;
            else
                error(sprintf("style %s is not supported", style));
            end

            if ~exist("baseZoom") || isempty(baseZoom)
                obj.baseZoom = 0;
            elseif isnumeric(baseZoom) && isscalar(baseZoom)
                obj.baseZoom = baseZoom;
            else
                error("given baseZoom is not supported")
            end
        end

        function asyncRedraw(obj)
        %ASYNCREDRAW schedules a redraw very soon
        %   This is called every time the axis limits change, i.e. on every
        %   pan or zoom. To avoid stuttering, all downloading and
        %   redrawing is done asynchronously

            % If the user is panning, this function is triggered very often.
            % But only the latest redraw task needs to survive:
            timers = timerfindall("Tag", "mapredraw");
            if ~isempty(timers)
                stop(timers)
            end

            t = timer();
            function timerCallback(~, ~)
                obj.redraw();
            end
            t.TimerFcn = @timerCallback;
            t.BusyMode = "queue";
            % make sure the timer doesn't stay around when it's done:
            t.StopFcn = @(~,~)delete(t);
            % set a short delay, otherwise start(t) blocks:
            t.StartDelay = 0.1;
            t.Tag = "mapredraw";
            start(t);
        end

        function redraw(obj)
        %REDRAW (re-) draws the map
        %   according to obj.coords, obj.style, and obj.zoomLevel.
        %   Map tiles are downloaded from OSM if necessary.
        %   Already downloaded tiles are not re-downloaded.
        %   Map tiles are always drawn below all other plot elements.
        %   The plot aspect ratio is changed to match the map tiles.

            if isempty(obj.style)
                return
            end

            if ~ishandle(obj.ax)
                error("can't draw on closed axes");
            end

            [minX, maxX, minY, maxY] = obj.tileIndices();

            aspectRatio = diff(obj.ax.XLim)/diff(obj.ax.YLim);
            % correct skewing due to mercator projection:
            % (http://wiki.openstreetmap.org/wiki/ ...
            %  Slippy_map_tilenames#Resolution_and_Scale)
            mercatorCorrection = cos(mean(obj.ax.YLim)/180*pi);
            obj.ax.PlotBoxAspectRatio = [mercatorCorrection*aspectRatio, 1, 1];

            function yesNo = isCurrent(im)
            %ISCURRENT identifies current images
                yesNo = im.UserData.zoom == obj.zoomLevel && ...
                        strcmp(im.UserData.style, obj.style);
            end
            allTiles = findobj(obj.ax.Children, "Tag", "maptile");
            if ~isempty(allTiles)
                % bring all current tiles to the top of the tile stack,
                % by pushing all non-current tiles to the bottom.
                % (we don't push tiles to the top, to prevent drawing
                %  over user-created plots)
                nonCurrentTiles = allTiles(~arrayfun(@isCurrent, allTiles));
                if ~isempty(nonCurrentTiles)
                    uistack(nonCurrentTiles, "bottom");
                end
            end
            % this is the offset of the tiles in the drawing order.
            % Anything above this is user-generated. We should never
            % draw above this.
            stackPositionFromTop = length(obj.ax.Children)-length(allTiles);

            timers = timerfindall("Tag", "tileDownload");
            if ~isempty(timers)
                stop(timers)
            end

            % download tiles in a one-tile radius around the plot area,
            % to enable the user to pan a bit without hitting empty tiles:
            for x=max(0, (minX-1)):min((maxX+1), 2^obj.zoomLevel-1)
                for y=max(0, (minY-1)):min((maxY+1), 2^obj.zoomLevel-1)
                    t = timer();
                    timerCallback = @(~,~) obj.drawTile(x, y, minX, maxX, minY, maxY, stackPositionFromTop);
                    t.TimerFcn = timerCallback;
                    t.BusyMode = "queue";
                    % make sure the timer doesn't stay around when it's done:
                    t.StopFcn = @(~,~)delete(t);
                    % set a short delay, otherwise start(t) blocks:
                    t.StartDelay = 0.01;
                    t.Tag = "tileDownload";
                end
            end
            start(timerfindall("Tag", "tileDownload"));
        end

        function drawTile(obj, x, y, minX, maxX, minY, maxY, stackPositionFromTop)
            if ~isempty(obj.searchCache(x, y))
                return
            end

            try
                imagedata = obj.downloadTile(x, y);
            catch
                warning("couldn't download tile at " + ...
                        obj.formatLatLon(obj.y2lat(y), ...
                                         obj.x2lon(x)) + ...
                        sprintf(" (zoom level %i)", ...
                                obj.zoomLevel));
                return
            end

            im = image(obj.ax, ...
                       obj.x2lon([x, x+1]), ...
                       obj.y2lat([y, y+1]), ...
                       imagedata);
            im.UserData = struct("x", x, "y", y, ...
                                 "zoom", obj.zoomLevel, ...
                                 "style", obj.style);
            im.Tag = "maptile";

            % make sure the tile is drawn below other plots:
            uistack(im, "down", stackPositionFromTop);

            % skip drawing updated invisible tiles for performance
            if x >= minX && x <= maxX && y >= minY && y <= maxY
                drawnow();
            end
        end

        function coords = get.coords(obj)
            coords = struct("minLon", obj.ax.XLim(1), ...
                            "maxLon", obj.ax.XLim(2), ...
                            "minLat", obj.ax.YLim(1), ...
                            "maxLat", obj.ax.YLim(2));
        end

        function set.coords(obj, coords)
            % this will trigger a redraw due to the YLim listener:
            obj.ax.XLim = [coords.minLon, coords.maxLon];
            obj.ax.YLim = [coords.minLat, coords.maxLat];
        end

        function zoom = get.zoomLevel(obj)
            % get minimum number of tiles for ax size:
            pixelShape = getpixelposition(obj.ax);
            minLatTiles = ceil(pixelShape(3) / 256);
            minLonTiles = ceil(pixelShape(4) / 256);
            % get zoom level of ax width/height
            latHeight = diff(obj.ax.YLim);
            latZoom = ceil(log2(170.1022/latHeight));
            lonWidth = diff(obj.ax.XLim);
            lonZoom = ceil(log2(360/lonWidth));
            % combine to tile zoom level:
            zoom = min([lonZoom+minLonTiles, latZoom+minLatTiles]);
            zoom = zoom + obj.baseZoom;
            zoom = min([zoom, 18]);
            zoom = max([0, zoom]);
        end

        function set.style(obj, style)
            if ~isfield(obj.urls, style)
                % format nice error message:
                validFields = fieldnames(obj.urls);
                % format field names for listing them:
                validFields = cellfun(@(f)["'" f "' "], validFields, ...
                                      "uniformoutput", false);
                error(["style must be one of ", ...
                       [validFields{:}]]);
            end
            obj.style = style;
            obj.asyncRedraw();
        end

        function styles = get.possibleStyles(obj)
            styles = fieldnames(obj.urls);
        end

        function [minX, maxX, minY, maxY] = tileIndices(obj)
        %TILEINDICES returns tile indices for the current coords
        %   according to obj.zoomLevel.

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
        %DOWNLOADTILE at index X and Y
        %   according to obj.style and obj.zoomLevel.

            baseurl = obj.urls.(obj.style);
            url = sprintf("%s/%i/%d/%d.png", baseurl, obj.zoomLevel, x, y);
            [indices, cmap] = imread(url);
            imagedata = ind2rgb(indices, cmap);
        end

        function x = lon2x(obj, lon)
        %LON2X convert longitude in degrees to x tile index
        %   according to obj.zoomLevel.

            x = floor(2^obj.zoomLevel * ((lon + 180) / 360));
        end

        function y = lat2y(obj, lat)
        %LAT2Y convert latitude in degrees to y tile index
        %   according to obj.zoomLevel.

            lat = lat / 180 * pi;
            y = floor(2^obj.zoomLevel * (1 - (log(tan(lat) + sec(lat)) / pi)) / 2);
            y = real(y); % prevent error for invalid lat
        end

        function lon = x2lon(obj, x)
        %X2LON convert x tile index to longitude in degrees
        %   according to obj.zoomLevel.

            lon = x / 2^obj.zoomLevel * 360 - 180;
        end

        function lat = y2lat(obj, y)
        %Y2LAT convert y tile index to latitude in degrees
        %   according to obj.zoomLevel.

            lat_rad = atan(sinh(pi * (1 - 2 * y / (2^obj.zoomLevel))));
            lat = lat_rad * 180 / pi;
        end

        function str = formatLatLon(obj, lat, lon)
        %FORMATLATLON returns string representation oflatitude and longitude

            str = "";
            if lat > 0
                str = str + sprintf("%.3f N, ", lat);
            else
                str = str + sprintf("%.3f S, ", -lat);
            end
            if lon > 0
                str = str + sprintf("%.3f E", lon);
            else
                str = str + sprintf("%.3f W", -lon);
            end
        end

        function im = searchCache(obj, x, y)
        %SEARCHCACHE looks for tile image in obj.ax.Children
        %   according to obj.zoomLevel and obj.style.
        %   Returns [] if no matching tile image is found.
        %   Returns an image instance otherwise.

            im = [];
            tiles = findobj(obj.ax.Children, "Tag", "maptile");
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
