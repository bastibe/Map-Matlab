classdef Mapper < handle
    properties (Hidden)
        fig
        map
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
            mapax = axes(obj.fig);
            mapax.Position = [0.05, 0.15, 0.9, 0.7];
            obj.map = Map(mapax);
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
            place = urlencode(place);
            url = sprintf('%s?&address=%s', baseurl, place);
            data = jsondecode(urlread(url));
            geometry = data.results.geometry.bounds;
            coords = struct('minLon', geometry.southwest.lng, ...
                            'maxLon', geometry.northeast.lng, ...
                            'minLat', geometry.southwest.lat, ...
                            'maxLat', geometry.northeast.lat);
        end

        function set.place(obj, place)
            try
                coords = obj.downloadCoords(place);
            catch
                obj.activityLabel.String = ['can''t find ' place];
                pause(1);
                return
            end
            obj.setCoordsAsync(coords);
            % set axis limits to the new place as well
            obj.map.ax.XLim = [coords.minLon, coords.maxLon];
            obj.map.ax.YLim = [coords.minLat, coords.maxLat];

            obj.place = place;
        end

        function set.style(obj, style)
            obj.map.style = style;
            obj.style = style;
        end

        function placeEditCallback(obj, target, event)
            obj.place = target.String;
        end

        function styleSelectCallback(obj, target, event)
            obj.style = target.String{target.Value};
        end

        function panZoomCallback(obj, target, event)
            if event.Axes ~= obj.map.ax
                return
            end
            coords = struct('minLon', obj.map.ax.XLim(1), ...
                            'maxLon', obj.map.ax.XLim(2), ...
                            'minLat', obj.map.ax.YLim(1), ...
                            'maxLat', obj.map.ax.YLim(2));
            obj.setCoordsAsync(coords);
        end

        function setCoordsAsync(obj, coords)
        % The point of this function is to call obj.map.coords = coords
        % However, this operation can take some time, since new tiles
        % might be downloaded from the internet. For some arcane reason,
        % zoom/pan callbacks in Matlab CAN NOT TAKE TIME. Thus, this
        % function relegates the operation to a timer, which will
        % execute at a later time, without blocking the callback.
            t = timer();
            function timerCallback(~, ~)
                obj.activityLabel.String = 'Downloading...';
                obj.map.coords = coords;
                obj.activityLabel.String = '';
            end
            t.TimerFcn = @timerCallback;
            t.BusyMode = 'queue';
            % make sure the timer doesn't stay around when it's done:
            t.StopFcn = @(~,~)delete(t);
            % set a short delay, otherwise start(t) blocks:
            t.StartDelay = 0.01;
            start(t);
        end
    end
end
