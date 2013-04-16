/**
* Setup for ScreenCapture plugin use with Cordova. 
*/
//Options Class for ScreenCapture
function ScreenCaptureOptions() {
	this.x = 0;
	this.y = 0;
	this.width = -1;
	this.height = -1;
	this.fileName = "screenshot";
	this.asynchronous = false;
}
function CompareOptions(compareURL) {
	this.compareURL = compareURL;
	this.colorTolerance = 0.0;
	this.pixelTolerance = 0.0;
	this.writeActualToFile = false;
	this.writeDiffToFile = false;	
	this.binaryDiff = false;
}


//Global Variables
window.delayBeforeCapture = 200; //the number of milliseconds to wait to allow the WebView to update before calling capture

//This assigns the capture function to the window for calling within Javascript.  window.capture will call cordova.exec with a string literal to 
//indicate that we want to call "capture" function in ScreenCapture.java
window.capture = function(callback, errorCallBack, captureOptions) {
	cordova.exec(callback, errorCallBack, "ScreenCapture", "capture",[captureOptions]);
}

window.captureAndCompare = function(callback, errorCallBack,captureOptions,compareOptions) {
	cordova.exec(callback, errorCallBack, "ScreenCapture", "captureAndCompare", [captureOptions,compareOptions]);
}

/*** Capture API ***/
//call the native capture function after a set amount of time to allow the screen to update with desired changes
function callCaptureDelay(callBack, errorCallBack, captureOptions) {
	window.captureComplete = false;
	setTimeout(function(){window.capture(callBack, errorCallBack, captureOptions);}, window.delayBeforeCapture);	
}
/*** CaptureAndCompare API ***/
//call the native capture function after a set amount of time, then compare against the expected image that is specified in compareOptions
function callCaptureAndCompareDelay(callBack, errorCallBack, captureOptions, compareOptions) {
	window.captureComplete = false;
	setTimeout(function(){window.captureAndCompare(callBack, errorCallBack, captureOptions, compareOptions)},window.delayBeforeCapture);		
}