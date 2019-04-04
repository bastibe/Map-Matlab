classdef Mapper < handle
%MAPPER is a simple GUI for a map
%   The user can select a place and a style for the map. The place will be
%   converted to latitude/longitude coordinates using the Google geocoding API.

% Copyright (c) 2017, Bastian Bechtold
% This code is released under the terms of the BSD 3-clause license

    properties
        fig           % the figure to draw on
        map           % the map instance
    end

    properties (Hidden)
        placeLabel    % text label for the place edit field
        placeEdit     % edit field for the place
        styleLabel    % text label for the style edit field
        stylePopup    % popup menu for the map style
    end

    methods
        function obj = Mapper(place, style)
        %MAPPER creates a new mapper instance at place with style

            obj.fig = uifigure();
            grid = uigridlayout(obj.fig);
            grid.RowHeight = {30, "1x"};
            grid.ColumnWidth = {50 100 "1x" 50 100};

            obj.placeLabel = uilabel(grid);
            obj.placeLabel.Text = "Place:";
            obj.placeLabel.Layout.Row = 1;
            obj.placeLabel.Layout.Column = 1;

            obj.placeEdit = uieditfield(grid);
            obj.placeEdit.Layout.Row = 1;
            obj.placeEdit.Layout.Column = 2;
            obj.placeEdit.HorizontalAlignment = "left";
            obj.placeEdit.ValueChangedFcn = @obj.placeEditCallback;
            if exist("place") && ~isempty(place)
                obj.placeEdit.Value = place;
            end

            obj.styleLabel = uilabel(grid);
            obj.styleLabel.Text = "Style:";
            obj.styleLabel.Layout.Row = 1;
            obj.styleLabel.Layout.Column = 4;

            obj.stylePopup = uidropdown(grid);
            obj.stylePopup.Layout.Row = 1;
            obj.stylePopup.Layout.Column = 5;
            obj.stylePopup.ValueChangedFcn = @obj.styleSelectCallback;

            mapax = uiaxes(grid);
            mapax.Layout.Row = 2;
            mapax.Layout.Column = [1 5];

            drawnow();
            obj.map = Map([], [], mapax, -1);
            obj.stylePopup.Items = obj.map.possibleStyles;
            obj.stylePopup.Value = obj.map.style;

            if ~exist("place")
                place = [];
            elseif ~isempty(place)
                obj.setPlace(place);
            end
            if ~exist("style")
                style = [];
            elseif ~isempty(style)
                obj.map.style = style;
            end
        end

        function delete(obj)
        % close the figure when dieing
            if ishandle(obj.fig)
                close(obj.fig);
            end
        end

        function coords = downloadCoords(obj, place)
        %DOWNLOADCOORDS downloads longitude/latitude coordinates for a place
        %   using the google geocoding API.
        %
        %   returns a struct with fields "minLon", "maxLon", "minLat", and
        %       "maxLat".

            baseurl = "https://nominatim.openstreetmap.org/search";
            place = urlencode(place);
            url = sprintf("%s?&city=%s&format=json", baseurl, place);
            data = jsondecode(urlread(url));
            if isstruct(data)
                bbox = data(1).boundingbox;
            elseif iscell(data)
                bbox = data{1}.boundingbox;
            end
            geometry = cellfun(@str2double, bbox);
            coords = struct("minLon", geometry(3), ...
                            "maxLon", geometry(4), ...
                            "minLat", geometry(1), ...
                            "maxLat", geometry(2));
            if coords.minLon > coords.maxLon
                [coords.minLon, coords.maxLon] = ...
                    deal(coords.maxLon, coords.minLon);
            end
            if coords.minLat > coords.maxLat
                [coords.minLat, coords.maxLat] = ...
                    deal(coords.maxLat, coords.minLat);
            end
        end

        function setPlace(obj, place)
        %SETPLACE sets coordinates of map according to place

            try
                coords = obj.downloadCoords(place);
            catch
                warning(["can't find " place]);
                return
            end
            obj.map.coords = coords;
        end

        function placeEditCallback(obj, target, event)
            obj.setPlace(target.Value);
        end

        function styleSelectCallback(obj, target, event)
            obj.map.style = target.Value;
        end
    end
end
