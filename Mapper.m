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

            obj.fig = figure();
            mapax = axes(obj.fig);
            mapax.Position = [0.05, 0.15, 0.9, 0.7];
            obj.map = Map([], [], mapax);
            if nargin < 1
                place = [];
            end
            if nargin < 2
                style = [];
            end
            if isempty(style)
                style = obj.map.style;
            end

            obj.placeLabel = uicontrol();
            obj.placeLabel.Style = "Text";
            obj.placeLabel.String = "Place:";
            obj.placeLabel.Units = "normalized";
            obj.placeLabel.Position = [0.1, 0.885, 0.15, 0.05];

            obj.placeEdit = uicontrol();
            obj.placeEdit.Style = "Edit";
            obj.placeEdit.Units = "normalized";
            obj.placeEdit.Position = [0.22, 0.89, 0.2, 0.05];
            obj.placeEdit.HorizontalAlignment = "left";
            obj.placeEdit.Callback = @obj.placeEditCallback;
            obj.placeEdit.String = place;

            obj.styleLabel = uicontrol();
            obj.styleLabel.Style = "Text";
            obj.styleLabel.String = "Style:";
            obj.styleLabel.Units = "normalized";
            obj.styleLabel.Position = [0.5, 0.885, 0.15, 0.05];

            obj.stylePopup = uicontrol();
            obj.stylePopup.Style = "Popupmenu";
            obj.stylePopup.Units = "normalized";
            obj.stylePopup.Position = [0.62, 0.89, 0.2, 0.05];
            obj.stylePopup.String = obj.map.possibleStyles;
            obj.stylePopup.Callback = @obj.styleSelectCallback;

            obj.map.style = style;
            obj.setPlace(place);
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
            obj.setPlace(target.String);
        end

        function styleSelectCallback(obj, target, event)
            obj.map.style = target.String{target.Value};
        end
    end
end
