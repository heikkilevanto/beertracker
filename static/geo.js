// geo.js - Various geolocation things mostly for geo.pm

function geoclear(prefix) {
  const latinp = document.getElementById(prefix+"Lat");
  const loninp = document.getElementById(prefix+"Lon");
  latinp.value = "";
  loninp.value = "";
  latinp.dispatchEvent(new Event("input"));
}

function geohere(prefix) {
  const latinp = document.getElementById(prefix+"Lat");
  const loninp = document.getElementById(prefix+"Lon");
  if (!navigator.geolocation) {
    console.log("Geolocation is not supported by your browser.");
    return;
  }
  navigator.geolocation.getCurrentPosition(
    function(pos) {
      latinp.value = pos.coords.latitude.toFixed(6);
      loninp.value = pos.coords.longitude.toFixed(6);
      latinp.dispatchEvent(new Event("input"));
    },
    function(err) {
      console.log("Geo Error: " + err.message);
    }
  );
}

function haversineKm(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth radius in km
  const toRad = Math.PI / 180;

  const dLat = (lat2 - lat1) * toRad;
  const dLon = (lon2 - lon1) * toRad;

  const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) *
            Math.sin(dLon / 2) ** 2;

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function geodist(prefix) {
  if (!navigator.geolocation) {
    return;
  }
  const latinp = document.getElementById(prefix+"Lat");
  const loninp = document.getElementById(prefix+"Lon");
  const distspan = document.getElementById(prefix+"Dist");
  if ( ! latinp.value || ! loninp.value ) {
    distspan.textContent = "...";
    return;
  }
  navigator.geolocation.getCurrentPosition(
    function(pos) {
      const lat1 = pos.coords.latitude.toFixed(7);
      const lon1 = pos.coords.longitude.toFixed(7);
      const lat2 = latinp.value;
      const lon2 = loninp.value;
      if ( lat2 && lon2 ) {
        var dist = haversineKm(lat1,lon1, lat2,lon2);
        if ( dist > 10 )
          dist = dist.toFixed(1) + " km";
        else if ( dist > 1 )
          dist = dist.toFixed(3) + " km";
        else
          dist = (dist * 1000)  .toFixed(0) + " m";

        distspan.textContent= " " + dist ;
      } else {
        distspan.textContent = "...";
      }

    },
    function(err) {
      console.log("Geo Error: " + err.message);
    }
  );
}
