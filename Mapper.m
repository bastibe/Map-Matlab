classdef Mapper < handle
    properties (Access='private')
        fig
        map
        mapax
        placeLabel
        placeEdit
        styleLabel
        stylePopup
        activityLabel
        panHandle
        zoomHandle
    end

    properties
        place = []
        style = []
    end

    methods
        function obj = Mapper(place, style)
            obj.fig = figure();
            obj.mapax = axes(obj.fig);
            obj.mapax.Position = [0.05, 0.15, 0.9, 0.7];
            obj.map = Map(obj.mapax);
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
            obj.placeEdit.String = place;

            obj.styleLabel = uicontrol();
            obj.styleLabel.Style = 'Text';
            obj.styleLabel.String = 'Style:';
            obj.styleLabel.Units = 'normalized';
            obj.styleLabel.Position = [0.5, 0.885, 0.15, 0.05];

            obj.stylePopup = uicontrol();
            obj.stylePopup.Style = 'Popupmenu';
            obj.stylePopup.Units = 'normalized';
            obj.stylePopup.Position = [0.62, 0.89, 0.2, 0.05];
            obj.stylePopup.String = obj.map.styles;
            obj.stylePopup.Callback = @obj.styleSelectCallback;

            obj.activityLabel = uicontrol();
            obj.activityLabel.Style = 'Text';
            obj.activityLabel.String = '';
            obj.activityLabel.Units = 'normalized';
            obj.activityLabel.HorizontalAlignment = 'center';
            obj.activityLabel.Position = [0.4, 0.02, 0.2, 0.05];

            obj.panHandle = pan(obj.fig);
            obj.panHandle.ActionPostCallback = @obj.panZoomCallback;
            obj.zoomHandle = zoom(obj.fig);
            obj.zoomHandle.ActionPostCallback = @obj.panZoomCallback;

            obj.style = style;
            obj.place = place;
        end

        function delete(obj)
            if ishandle(obj.fig)
                close(obj.fig);
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

        function lockPanZoom(obj)
            obj.activityLabel.String = 'Downloading...';
            setAllowAxesZoom(obj.zoomHandle, obj.mapax, false);
            setAllowAxesPan(obj.panHandle, obj.mapax, false);
            obj.placeEdit.Enable = 'off';
            obj.stylePopup.Enable = 'off';
            for tag={'Exploration.ZoomIn', ...
                     'Exploration.ZoomOut', ...
                     'Exploration.Pan'}
                button = findall(obj.fig, 'Tag', tag{1});
                button.Enable = 'off';
            end
        end

        function unlockPanZoom(obj)
            setAllowAxesPan(obj.panHandle, obj.mapax, true);
            setAllowAxesZoom(obj.zoomHandle, obj.mapax, true);
            obj.placeEdit.Enable = 'on';
            obj.stylePopup.Enable = 'on';
            for tag={'Exploration.ZoomIn', ...
                     'Exploration.ZoomOut', ...
                     'Exploration.Pan'}
                button = findall(obj.fig, 'Tag', tag{1});
                button.Enable = 'on';
            end
            obj.activityLabel.String = '';
        end

        function set.place(obj, place)
            obj.lockPanZoom();
            coords = obj.downloadCoords(place);
            obj.map.coords = coords;
            obj.place = place;
            obj.unlockPanZoom();
        end

        function set.style(obj, style)
            obj.lockPanZoom();
            obj.map.style = style;
            obj.style = style;
            obj.unlockPanZoom();
        end

        function placeEditCallback(obj, target, event)
            obj.lockPanZoom();
            obj.place = target.String;
            obj.unlockPanZoom();
        end

        function styleSelectCallback(obj, target, event)
            obj.lockPanZoom();
            obj.style = target.String{target.Value};
            obj.unlockPanZoom();
        end

        function panZoomCallback(obj, target, event)
            if event.Axes ~= obj.mapax
                return
            end
            obj.lockPanZoom();
            coords = struct('minLon', obj.mapax.XLim(1), ...
                            'maxLon', obj.mapax.XLim(2), ...
                            'minLat', obj.mapax.YLim(1), ...
                            'maxLat', obj.mapax.YLim(2));
            obj.map.coords = coords;
            obj.unlockPanZoom();
        end
    end
end
