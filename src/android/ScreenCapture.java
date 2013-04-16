package org.apache.cordova.plugin;

import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import org.apache.cordova.CordovaWebView;
import org.apache.cordova.api.CallbackContext;
import org.apache.cordova.api.CordovaInterface;
import org.apache.cordova.api.CordovaPlugin;
import org.apache.cordova.api.PluginResult;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Picture;
import android.graphics.Bitmap.CompressFormat;

import android.os.Environment;

/**
 * This Cordova plugin for Android allows taking a screenshot of the current content running on the device.  When
 * Execute is called from javascript this plugin will take a screenshot, with an optional subrect defined, and 
 * save the results to the sdcard.  The location of the file is then returned to Javascript in the callback function
 * supplied from Javascript.  This plugin also offers comparison of provided baseline images to enable automation of 
 * rendering behavior.
 */
public class ScreenCapture extends CordovaPlugin {
	private int mCaptureCount = 0; //internal counter that increments for each capture made, this is reflected in the resulting .png file
	private String mFileName = ""; //used to store what the user has specified for a filename, if it ever changes we will reset the counter
	//the url of the saved screenshot.  By default the plugin tries to save to the sdcard.  In the event there is no sdcard mounted, Android will
	//save to an emulated location at: mnt/shell/emulator/<user profile number>.  
	//You can access this location using ddms in the android SDK (android-sdk-windows\tools\lib\ddms.bat)
	
	
	/**
	 * execute is called from the cordova plugin framework
	 * @param args contains the coordinates for the subrect of the screen that is to be captured.  Order of arguments is: x, y, width, height
	 * @param callbackContext the callback function provided from javascript.  This function will be called upon completion of execute
	 */
	public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
		//if the fileName has changed, set the global and reset the counter
		JSONObject captureOptions = args.optJSONObject(0);
		
		if(action.equals("capture")){
			getScreenBitsAsync(
					callbackContext,
					captureOptions,
					null
					);
		}
		else if(action.equals("captureAndCompare")) {
			//get the options
			JSONObject compareOptions = args.optJSONObject(1);
			getScreenBitsAsync(
					callbackContext,
					captureOptions,
					compareOptions
					);
		}
		else {
			return false;
		}
		
		return true;
	}
	
	private void getScreenBitsAsync(final CallbackContext callback, final JSONObject captureOptions, final JSONObject compareOptions) {
		//parse the options on the core thread
		final CordovaInterface coreThreadCordova = this.cordova;
		final boolean async = captureOptions.optBoolean("asynchronous");
		
		// capture on the ui thread
		cordova.getActivity().runOnUiThread(new Runnable() {
            public void run() {
            	//determine if we have a new fileName and reset counter if so
            	String nameTemp = captureOptions.optString("fileName","screenshot");
            	if(nameTemp.equalsIgnoreCase("")) {
            		nameTemp = "screenshot";
            	}
            	if(!(nameTemp.equals(mFileName))) {
        			mFileName = nameTemp;
        			mCaptureCount = 0;
        		}
            	CordovaWebView uiThreadView = webView;
            	//capturePicture writes the entire document into a picture object, this includes areas that aren't visible within the current view
            	final Picture picture = uiThreadView.capturePicture();
            	final String fileName = mFileName+"_"+mCaptureCount;
            	mCaptureCount++;
            	
            	if(async) {
            		PluginResult result = new PluginResult(PluginResult.Status.OK, "capture taken");
            		result.setKeepCallback(true);
            		callback.sendPluginResult(result);
            	}
            	
            	//do file IO and optional compare on a background thread
        		cordova.getThreadPool().execute(new Runnable() {
        			public void run() {
        				 int x = captureOptions.optInt("x");
        				 int y = captureOptions.optInt("y");
        				 int width = captureOptions.optInt("width");
        				 int height = captureOptions.optInt("height");
        				
        				 //need to know if we want to write the actual file, option for compare, automatically true for capture
        				 boolean createActual = (compareOptions != null) ? compareOptions.optBoolean("writeActualToFile") : true; 
        						 
        				 String fileLocation = "";
        				 
        				 int[] internalPixels = new int[0];
        				 
        				 /**** Write Capture File Portion ****/
    					//copy whole picture into a bitmap
    					Bitmap bm = Bitmap.createBitmap(picture.getWidth(), picture.getHeight(), Bitmap.Config.ARGB_8888);
    					Canvas c = new Canvas(bm);
    					picture.draw(c);
    					
    					if(width > 0 && height > 0 && 
    							width < picture.getWidth() &&
    							height < picture.getHeight()) 
    					{
    						//clip to 0 if less than
    						x = (x < 0) ? 0 : x;
    						y = (y < 0) ? 0 : y;
    						//width and height > 0 means we want to sub rect
    						internalPixels = new int[width*height];
    						bm.getPixels(internalPixels, 0, width, x, y, width, height);
    						bm = Bitmap.createBitmap(internalPixels,width,height, Bitmap.Config.ARGB_8888);
    					}
    					else if(compareOptions != null) {
    						int w = picture.getWidth();
    						int h = picture.getHeight();
    						//no sub rect requested, but we want to do a compare so create the pixels
    						internalPixels = new int[w*h];
    						bm.getPixels(internalPixels, 0, w, x, y, w, h);
    					}
    					//else no subrect requested and no pixels back
    					if(compareOptions == null || createActual == true) {
    						//write only if we are in a pure capture function call, or our compareOptions wants an actual output
    						fileLocation = writeBitmapToFile(bm, fileName);
    					}
    					bm.recycle();
    					
    					
    					/**** Compare portion ****/
    					//we have a comparison url so we want to do a compare now
    					if(compareOptions != null) {
    						//set the options
    						String compareURL = compareOptions.optString("compareURL");
    						boolean createDiff = compareOptions.optBoolean("writeDiffToFile");
    						double colorTolerance = compareOptions.optDouble("colorTolerance");
    						double pixelTolerance = compareOptions.optDouble("pixelTolerance");
    						boolean binaryDiff = compareOptions.optBoolean("binaryDiff");
    						//clip tolerances to 0 - 1
    						if(colorTolerance < 0) 
    							colorTolerance = 0;
    						else if(colorTolerance > 1)
    							colorTolerance = 1;
    						if(pixelTolerance < 0) 
    							pixelTolerance = 0;
    						else if(pixelTolerance > 1)
    							pixelTolerance = 1;
    						
    						boolean fileNotFound = false;
    						int[] comparePixels;
    						int[] diffPixels = new int[0];
    						int numPixelsDifferent = 0;
    						int compareWidth, compareHeight;
    						String diffFileLocation = "";
    						InputStream is =null;
    						try {
    						    is=coreThreadCordova.getActivity().getAssets().open(compareURL);
    						} catch (IOException e) {
    							fileNotFound = true;
    						}
    						if(fileNotFound) {
    							//couldn't get it from assets, try the sdcard
    							try {
    								is = new FileInputStream(compareURL);
    							}
    							catch(IOException err) {
    								//could not find the file in assets or the sdcard, return a failure
    								callback.error("Error: Could not open compare image:"+err.getLocalizedMessage());
    							}
    						}
    						if(fileNotFound == false) {
	    						//decode the png into a bitmap
	    						bm = BitmapFactory.decodeStream(is);
	    						compareWidth = bm.getWidth();
	    						compareHeight = bm.getHeight();
	    						//create the correct size int[]
	    						comparePixels = new int[compareWidth * compareHeight];
	    						//setup our diff array if the user specified they want one
	    						if(createDiff) {
	    							diffPixels = new int[comparePixels.length];
	    						}
	    						//get the pixels for comparison
	    						bm.getPixels(comparePixels, 0, compareWidth, 0, 0, compareWidth, compareHeight);
	    						//compare the images
	    						if(comparePixels.length != internalPixels.length) {
	    							//the image sizes don't match callback error and abort the compare
	    							callback.error("Error: the actual and expected image are not the same size.");
	    						}
	    						else {
		    						numPixelsDifferent = compareImageData(internalPixels, comparePixels,colorTolerance, pixelTolerance, diffPixels, binaryDiff);
		    						//we have the diff, now create a diff file if requested and there is a difference
		    						if(createDiff && numPixelsDifferent > 0) {
		    							//create our bitmap
		    							Bitmap diffBitmap = Bitmap.createBitmap(compareWidth, compareHeight, Bitmap.Config.ARGB_8888);
		    				
		    							// Set the pixels
		    							diffBitmap.setPixels(diffPixels, 0, compareWidth, 0, 0, compareWidth, compareHeight);
		    							diffFileLocation = writeBitmapToFile(diffBitmap, (fileName+"_Diff"));
		    							diffBitmap.recycle();
		    						}
		    						bm.recycle();
		    						//even if async was true (ie we called the callback already), compare was also requested so use the callback to return the results
		    						PluginResult result = new PluginResult(PluginResult.Status.OK, numPixelsDifferent+" "+fileLocation+" "+diffFileLocation);
		    	            		result.setKeepCallback(false);
		    	            		callback.sendPluginResult(result);
	    						}
    						}
    						
    					}
    					//no compare url was given (ie capture only), return with just the fileLocation
    					else {
    						PluginResult result = new PluginResult(PluginResult.Status.OK, fileLocation);
    	            		result.setKeepCallback(false);
    						callback.success(fileLocation);
    					}
        				
        				
        			};
        		}); //end background thread file io and compare
            	
            }//end ui thread runnable.run
        });//end ui thread work
	}
	
	/**
	 * Compare the pixels provided by int[]'s within the given tolerances, write the file if desired
	 * @param data1 first image data for the compare
	 * @param data2 second image data for the compare
	 * @param colorTolerance the percentage the actual and baseline image can differ per each color channel before being considered a fail
	 * @param pixelTolerance the percentage the actual and baseline image can differ per total pixels before being considered a fail
	 * @param diffData optional return of the int[] containing the diff between data1 and data2.  If diffData is not null this will be returned
	 * @param binaryDiff flag to output any differences as a solid white pixel if true, if false the full difference in the values is written
	 * @return the number of pixels that fall outside the given tolerances
	 */
	//TODO: Account for the case that the images are not the same size.  You end up getting a 'stale reference' error when calling setPixels if they don't match
	private int compareImageData(int[] data1, int[] data2, double colorTolerance, double pixelTolerance, int[] diffData, boolean binaryDiff ) {
		int offCount = 0;
		int aDiff,rDiff,gDiff,bDiff, alpha1, alpha2, red1, red2, green1, green2, blue1, blue2;
		int wholeColorTolerance = Math.round((float)255 * (float)colorTolerance);
		boolean createDiff = (diffData.length == 0) ? false : true;
		
		
		//for each pixel compare each color channel versus the expected
		for(int i = 0; i < data1.length; i++) {
			//get the color value out of the packed int provided by Bitmap.getPixels
			alpha1 = (data1[i] >> 24) & 0xff;
			red1   = (data1[i] >> 16) & 0xff;
			green1 = (data1[i] >> 8) & 0xff;
			blue1  = (data1[i]) & 0xff;
			
			alpha2 = (data2[i] >> 24) & 0xff;
			red2   = (data2[i] >> 16) & 0xff;
			green2 = (data2[i] >> 8) & 0xff;
			blue2  = (data2[i]) & 0xff;
			
			//generate the difference 
			aDiff = Math.abs(alpha1 - alpha2);
			rDiff = Math.abs(red1 - red2);
			gDiff = Math.abs(green1 - green2);
			bDiff = Math.abs(blue1 - blue2);
			
            //compare each color with given tolerance, if any don't match fail this pixel
			if(  aDiff > wholeColorTolerance ||
	             rDiff > wholeColorTolerance ||	
	             gDiff > wholeColorTolerance ||
	             bDiff > wholeColorTolerance) {
            		//one or more channels are outside of tolerance, this pixel fails
            		offCount++;
            		if(createDiff) {
            			if(binaryDiff) {
            				diffData[i] = 0xffffffff;
            			}
            			else {
	            			//we want to be able to see differences, so write alpha as 255 so we don't get a blank bitmap
	            			diffData[i] = 0xff000000;
	            			//pack the rest of the colors into an int for uploading to a bitmap later
	            			diffData[i] |= (rDiff & 255) << 16;
	            			diffData[i] |= (gDiff & 255) << 8;
	            			diffData[i] |= (bDiff & 255);
            			}
            		}
            }
            else {
            	//pixel passes, so render black to indicate no difference
            	if(createDiff) {
            		diffData[i] = 0xff000000;
            	}
            }
            
		} //end pixel for loop
		
		//if our total number of failing pixels is within the tolerance, consider that no pixels failed
		if( ((double)offCount / data1.length ) <= pixelTolerance) {
			offCount = 0;
		}
		
		return offCount;
	}
	/**
	 * Helper function to write the given bitmap to a file with the specified name
	 * @param bm the bitmap to write
	 * @param fileName the name of the file to be written
	 * @return the location of the saved file, or an error message
	 */
	private String writeBitmapToFile(Bitmap bm, String fileName) {
		String fileLocation;
		OutputStream stream = null;
		try {
			fileLocation = Environment.getExternalStorageDirectory() +"/"+fileName+".png";
			stream = new FileOutputStream(fileLocation);
			bm.compress(CompressFormat.PNG, 80, stream);
			if (stream != null) stream.close();
		} catch (IOException e) {
			//imageLocation = "";
			return "Err: "+e.getLocalizedMessage();
		} 
		return fileLocation;
	}
}
