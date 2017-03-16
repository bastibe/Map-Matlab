fig = figure();
ax = axes();
coords = downloadCoords('Oldenburg');
m = Map(ax, coords, 'osm');
