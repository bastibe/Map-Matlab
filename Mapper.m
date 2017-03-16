classdef Mapper < handle
    properties (Access='private')
        fig
        map
        mapax
        pan
        placeLabel
        placeEdit
        styleLabel
        stylePopup
    end

    properties
        place = []
    end

    methods
        function obj = Mapper(place)
            obj.fig = figure();
            obj.mapax = axes(obj.fig);
            obj.mapax.Position = [0.05, 0.15, 0.9, 0.7];
            obj.map = Map(obj.mapax);
            if nargin == 1
                obj.place = place;
            end
            obj.pan = pan(obj.fig);
            obj.pan.ActionPostCallback = @obj.panCallback;


            obj.placeLabel = uicontrol();
            obj.placeLabel.Style = 'Text';
            obj.placeLabel.String = 'Place:';
            obj.placeLabel.Units = 'normalized';
            obj.placeLabel.Position = [0.1, 0.885, 0.15, 0.05];

            obj.placeEdit = uicontrol();
            obj.placeEdit.Style = 'Edit';
            obj.placeEdit.Units = 'normalized';
            obj.placeEdit.Position = [0.22, 0.89, 0.2, 0.05];
            obj.placeEdit.HorizontalAlignment = 'left';
            obj.placeEdit.Callback = @obj.placeEditCallback;
            obj.placeEdit.String = obj.place;


            obj.styleLabel = uicontrol();
            obj.styleLabel.Style = 'Text';
            obj.styleLabel.String = 'Style:';
            obj.styleLabel.Units = 'normalized';
            obj.styleLabel.Position = [0.5, 0.885, 0.15, 0.05];

            obj.stylePopup = uicontrol();
            obj.stylePopup.Style = 'Popupmenu';
            obj.stylePopup.Units = 'normalized';
            obj.stylePopup.Position = [0.72, 0.89, 0.2, 0.05];
            obj.stylePopup.String = obj.map.styles;
            obj.stylePopup.Callback = @obj.styleSelectCallback;
        end

        function delete(obj)
            if ishandle(obj.fig)
                close(obj.fig);
            end
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

        function placeEditCallback(obj, target, event)
            obj.place = target.String;
        end

        function styleSelectCallback(obj, target, event)
            obj.map.style = target.String{target.Value};
        end

        function panCallback(obj, target, event)
            if event.Axes ~= obj.mapax
                return
            end
            coords = struct('minLon', obj.mapax.XLim(1), ...
                            'maxLon', obj.mapax.XLim(2), ...
                            'minLat', obj.mapax.YLim(1), ...
                            'maxLat', obj.mapax.YLim(2));
            obj.map.coords = coords;
        end
    end
end
