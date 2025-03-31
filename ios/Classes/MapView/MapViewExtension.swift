//
//  MapViewExtension.swift
//  apple_maps_flutter
//
//  Created by Luis Thein on 22.09.19.
//

import Foundation
import UIKit
import MapKit

public extension MKMapView {
    // keeps track of the Map values
    private struct Holder {
        static var _zoomLevel: Double = Double(0)
        static var _pitch: CGFloat = CGFloat(0)
        static var _heading: CLLocationDirection = CLLocationDirection(0)
        static var _maxZoomLevel: Double = Double(21)
        static var _minZoomLevel: Double = Double(0)
    }
    
    var maxZoomLevel: Double {
        set { Holder._maxZoomLevel = newValue }
        get { Holder._maxZoomLevel }
    }
    
    var minZoomLevel: Double {
        set { Holder._minZoomLevel = newValue }
        get { Holder._minZoomLevel }
    }
    
    var zoomLevel: Double {
        get { Holder._zoomLevel }
    }
    
    var calculatedZoomLevel: Double {
        get {
            let centerPixelSpaceX = Utils.longitudeToPixelSpaceX(longitude: self.centerCoordinate.longitude)

            let lonLeft = self.centerCoordinate.longitude - (self.region.span.longitudeDelta / 2)

            let leftPixelSpaceX = Utils.longitudeToPixelSpaceX(longitude: lonLeft)
            let pixelSpaceWidth = abs(centerPixelSpaceX - leftPixelSpaceX) * 2

            let zoomScale = pixelSpaceWidth / Double(self.bounds.size.width)

            let zoomExponent = Utils.logC(val: zoomScale, forBase: 2)

            var zoomLevel = 21 - zoomExponent
            
            zoomLevel = Utils.roundToTwoDecimalPlaces(number: zoomLevel)
            
            Holder._zoomLevel = zoomLevel
            
            return zoomLevel
            
        }
        set (newZoomLevel) {
            Holder._zoomLevel = newZoomLevel
        }
    }
    
    func setCenterCoordinate(_ positionData: [String: Any], animated: Bool) {
        // 1. Grab target lat/lng from `positionData`
        let targetList = positionData["target"] as? [CLLocationDegrees]
            ?? [self.camera.centerCoordinate.latitude, self.camera.centerCoordinate.longitude]
        
        let centerCoordinate = CLLocationCoordinate2D(latitude: targetList[0],
                                                      longitude: targetList[1])
        
        // 2. If you pass in "zoom" from Flutter, store it – but we won't forcibly clamp.
        let zoom = positionData["zoom"] as? Double
        Holder._zoomLevel = zoom ?? Holder._zoomLevel

        // 3. If you pass pitch / heading, we ignore them or forcibly set them to 0 for “flat”.
        Holder._pitch = 0
        Holder._heading = 0
        
        // Also flatten camera (pure 2D):
        self.camera.pitch = 0
        self.camera.heading = 0
        
        // 4. Simply create a region from the center and a guess at lat/lng delta.
        //    This is a naive approach. Another option is to pick your own latDelta
        //    based on "zoom" if you want. For example:
        let regionSpan = regionSpanFor(zoomLevel: zoom ?? 5)
        let region = MKCoordinateRegion(center: centerCoordinate, span: regionSpan)
        
        // 5. Set the region
        self.setRegion(region, animated: animated)
    }

    /// A simple function that returns a “span” for a given “zoom.”
    /// You can come up with your own formula or store a table of latDelta per zoom.
    private func regionSpanFor(zoomLevel: Double) -> MKCoordinateSpan {
        var correctedZoom = zoomLevel - 0.66
        // This is extremely simplified. Modify as you wish.
        // Let's say each "zoomLevel" is 2^zoom in world coverage
        // A typical approach might map an integer “tile zoom” to latDelta ~ 360 / 2^zoom
        let clampedZoom = max(0, min(correctedZoom, 21)) // optional clamp 0..21
        let latDelta = 360 / pow(2, clampedZoom)
        return MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: latDelta)
    }
    // If you don’t want Apple’s bounding logic at all, you can remove setBounds or
    // keep it but avoid calling it from your Swift plugin.
    func setBounds(_ positionData: [String: Any], animated: Bool) {
        guard let coordsArray = positionData["target"] as? [[CLLocationDegrees]],
              !coordsArray.isEmpty
        else { return }
        
        let padding = positionData["padding"] as? Double ?? 0
        let coords = coordsArray.map { CLLocationCoordinate2D(latitude: $0[0], longitude: $0[1]) }
        guard let mapRect = coords.mapRect() else { return }
        
        self.setVisibleMapRect(mapRect, edgePadding: UIEdgeInsets(top: CGFloat(padding),
                                                                  left: CGFloat(padding),
                                                                  bottom: CGFloat(padding),
                                                                  right: CGFloat(padding)),
                               animated: animated)
    }
    
    /// A simpler “region” approach that does not force pitch or heading
    /// or altitude. You can still tweak the zoom by adjusting latDelta.
    func setCenterCoordinateRegion(centerCoordinate: CLLocationCoordinate2D,
                                   zoomLevel: Double,
                                   animated: Bool) {
        // No altitude, no clamp. Just store the new zoom in our Holder if needed.
        Holder._zoomLevel = zoomLevel

        // Flatten camera
        // Flatten camera
        Holder._pitch = 0
        Holder._heading = 0
        self.camera.pitch = 0
        self.camera.heading = 0
        
        // Example region from the simple function above:
        let regionSpan = regionSpanFor(zoomLevel: zoomLevel)
        let region = MKCoordinateRegion(center: centerCoordinate, span: regionSpan)
        
        self.setRegion(region, animated: animated)
    }
    
    func coordinateSpanWithMapView(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Int) -> MKCoordinateSpan  {
        // convert center coordiate to pixel space
        let centerPixelX = Utils.longitudeToPixelSpaceX(longitude: centerCoordinate.longitude)
        let centerPixelY = Utils.latitudeToPixelSpaceY(latitude: centerCoordinate.latitude)
    
        // determine the scale value from the zoom level
        let zoomExponent = Double(21 - zoomLevel)
        let zoomScale = pow(2.0, zoomExponent)

        // scale the map’s size in pixel space
        let mapSizeInPixels = self.bounds.size
        let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale;
    
        // figure out the position of the top-left pixel
        let topLeftPixelX = centerPixelX - (scaledMapWidth / 2);
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2);
    
        // find delta between left and right longitudes
        let minLng = Utils.pixelSpaceXToLongitude(pixelX: topLeftPixelX)
        let maxLng = Utils.pixelSpaceXToLongitude(pixelX: topLeftPixelX + scaledMapWidth)
        let longitudeDelta = maxLng - minLng;
    
        // find delta between top and bottom latitudes
        let minLat = Utils.pixelSpaceYToLatitude(pixelY: topLeftPixelY)
        let maxLat = Utils.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)
        let latitudeDelta = -1 * (maxLat - minLat)
    
        // create and return the lat/lng span
        return MKCoordinateSpan.init(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }
    
    // If you want, you can remove the entire “altitude” code. For completeness:
    @available(iOS 9.0, *)
    func setCenterCoordinateWithAltitude(centerCoordinate: CLLocationCoordinate2D,
                                         zoomLevel: Double,
                                         animated: Bool) {
        // TOTALLY remove altitude usage.  Just call setCenterCoordinateRegion:
        setCenterCoordinateRegion(centerCoordinate: centerCoordinate,
                                  zoomLevel: zoomLevel,
                                  animated: animated)
    }
    
    private func getCameraAltitude(centerCoordinate: CLLocationCoordinate2D, zoomLevel: Double) -> Double {
        // convert center coordiate to pixel space
        let centerPixelY = Utils.latitudeToPixelSpaceY(latitude: centerCoordinate.latitude)
        // determine the scale value from the zoom level
        let zoomExponent:Double = 21.0 - zoomLevel
        let zoomScale:Double = pow(2.0, zoomExponent)
        // scale the map’s size in pixel space
        let mapSizeInPixels = self.bounds.size
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale
        // figure out the position of the top-left pixel
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2.0)
        // find delta between left and right longitudes
        let maxLat = Utils.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)
        let topBottom = CLLocationCoordinate2D.init(latitude: maxLat, longitude: centerCoordinate.longitude)
        
        let distance = MKMapPoint.init(centerCoordinate).distance(to: MKMapPoint.init(topBottom))
        let altitude = distance / tan(.pi*(15/180.0))
        
        return altitude
    }
     /// Keep or remove as you prefer:
    func getVisibleRegion() -> [String: [Double]] {
        if self.bounds.size == .zero {
            return ["northeast": [0.0, 0.0], "southwest": [0.0, 0.0]]
        }
        
        // We still do the typical approach from the old code:
        let centerPixelX = Utils.longitudeToPixelSpaceX(longitude: self.centerCoordinate.longitude)
        let centerPixelY = Utils.latitudeToPixelSpaceY(latitude: self.centerCoordinate.latitude)

        let zoomExponent = Double(21 - Holder._zoomLevel)
        let zoomScale = pow(2.0, zoomExponent)

        let mapSizeInPixels = self.bounds.size
        let scaledMapWidth = Double(mapSizeInPixels.width) * zoomScale
        let scaledMapHeight = Double(mapSizeInPixels.height) * zoomScale

        let topLeftPixelX = centerPixelX - (scaledMapWidth / 2)
        let topLeftPixelY = centerPixelY - (scaledMapHeight / 2)

        let minLng = Utils.pixelSpaceXToLongitude(pixelX: topLeftPixelX)
        let minLat = Utils.pixelSpaceYToLatitude(pixelY: topLeftPixelY)

        let maxLng = Utils.pixelSpaceXToLongitude(pixelX: topLeftPixelX + scaledMapWidth)
        let maxLat = Utils.pixelSpaceYToLatitude(pixelY: topLeftPixelY + scaledMapHeight)

        return [
            "northeast": [minLat, maxLng],
            "southwest": [maxLat, minLng]
        ]
    }
    
    func zoomIn(animated: Bool) {
        if Holder._zoomLevel - 1 <= Holder._maxZoomLevel {
            if Holder._zoomLevel < 2 {
                Holder._zoomLevel = 2
            }
            Holder._zoomLevel += 1
            if #available(iOS 9.0, *) {
                self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            } else {
                self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            }
        }
    }
    
    func zoomOut(animated: Bool) {
        if Holder._zoomLevel - 1 >= Holder._minZoomLevel {
            Holder._zoomLevel -= 1
            if round(Holder._zoomLevel) <= 2 {
               Holder._zoomLevel = 0
            }

            if #available(iOS 9.0, *) {
               self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            } else {
               self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
            }
        }
    }
    
    func zoomTo(newZoomLevel: Double, animated: Bool) {
        if newZoomLevel < Holder._minZoomLevel {
            Holder._zoomLevel = Holder._minZoomLevel
        } else if newZoomLevel > Holder._maxZoomLevel {
            Holder._zoomLevel = Holder._maxZoomLevel
        } else {
            Holder._zoomLevel = newZoomLevel
        }

        if #available(iOS 9.0, *) {
            self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        } else {
            self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        }
    }
    
    func zoomBy(zoomBy: Double, animated: Bool) {
        if Holder._zoomLevel + zoomBy < Holder._minZoomLevel {
            Holder._zoomLevel = Holder._minZoomLevel
        } else if Holder._zoomLevel + zoomBy > Holder._maxZoomLevel {
            Holder._zoomLevel = Holder._maxZoomLevel
        } else {
            Holder._zoomLevel = Holder._zoomLevel + zoomBy
        }
        
        if #available(iOS 9.0, *) {
            self.setCenterCoordinateWithAltitude(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        } else {
            self.setCenterCoordinateRegion(centerCoordinate: centerCoordinate, zoomLevel: Holder._zoomLevel, animated: animated)
        }
    }
    
    func updateStoredCameraValues(newZoomLevel: Double, newPitch: CGFloat, newHeading: CLLocationDirection) {
        Holder._zoomLevel = newZoomLevel
        Holder._pitch = newPitch
        Holder._heading = newHeading
    }
}

// MARK: - Helpers for bounding a set of coordinates
extension Array where Element == CLLocationCoordinate2D {
    func mapRect() -> MKMapRect? {
        guard !isEmpty else { return nil }
        return map(MKMapPoint.init).mapRect()
    }
}

extension Array where Element == CLLocation {
    func mapRect() -> MKMapRect? {
        return map { MKMapPoint($0.coordinate) }.mapRect()
    }
}

extension Array where Element == MKMapPoint {
    func mapRect() -> MKMapRect? {
        guard !isEmpty else { return nil }

        let xs = map { $0.x }
        let ys = map { $0.y }
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max()
        else { return nil }

        let width = maxX - minX
        let height = maxY - minY
        return MKMapRect(x: minX, y: minY, width: width, height: height)
    }
}