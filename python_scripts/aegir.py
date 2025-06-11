import argparse
import logging.handlers
from pathlib import Path
import json
import os, sys
from dotenv import load_dotenv
import traceback
from datetime import datetime, timedelta
from time import time, sleep
import logging
import ms5837

import focus
import routine
import session
import device_interface
from device_interface import convert_time
import queue
from cam_image import get_fast_saturation_fraction

env_location = Path(__file__).parent.parent / ".env"
load_dotenv(env_location)

DATA_DIR = Path(os.environ.get("DATA_DIRECTORY"))
PIPE_IN_FILE = Path(os.environ.get("PIPE_IN_FILE"))
PIPE_OUT_FILE = Path(os.environ.get("PIPE_OUT_FILE"))

def main(log_queue:queue.Queue=None):
    """Loads a session and routine from arguments passed when calling the script.
    Call from command line with:
    $> auto_capture.py --routine [routine name] --session [session name]
    
    The order of arguments is not important.
    
    The script opens or creates a session with the name in the --session arg.
    If it can find a routine with the name in the --routine arg it will run that, 
    otherwise it will exit with error code 1.
    
    """    

    logger = logging.getLogger()
    
    #Argparse is a library used for parsing arguments passed to the script when it is called from the command line
    parser = argparse.ArgumentParser(description='Get session and routine arguments')

    # Set up the named arguments
    parser.add_argument('--routine', required=False, help='Set routine name')
    parser.add_argument('--session',required=False, help='Set session name')
    parser.add_argument('--focus',action='store_true', required=False, help='Run focus check script')
    parser.add_argument('--autostart', action='store_true', required=False, help='Starting in autostart mode')
        

    # Parse command line arguments
    args = parser.parse_args()

    # Access the values of named arguments
    routine_name:str = args.routine
    session_name:str = args.session
    focus_check:bool = args.focus
    auto_start:bool = args.autostart
    if focus_check:
        focus.run_focus_script()
        sys.exit(0)


    if auto_start:
        logger.info("Autostart mode")

    current_session: session.Session = None
    current_routine: routine.Routine = None


    
    if routine_name is None:
        logger.error(f'Routine Name not specified. Exiting.')
        sys.exit(0)

    if session_name == "":
        session_name = None

    logger.info(f'Routine Name: {routine_name}')
    if session_name is None:
        logger.info(f'Session Name not set. Using starting timestamp.')
    else:
        logger.info(f'Session Name: {session_name}')
    

    #Attempt to open connection to the device - exit with error code 1 if not
    
    device = device_interface.open()
    if not device:
        logger.critical("Could not connect to Device")
        # log_error(message="Could not connect to Device")
        sys.exit(1)

    #Attempt to open connection to the pressure sensor - exit with error code 1 if not
    
    try:
        sensor = ms5837.MS5837_30BA()
        if not sensor.init():
            logger.critical("Could not connect to Pressure Sensor")
            logger.critical("Exiting")
            # log_error(message="Could not connect to Pressure Sensor")
            sys.exit(1)
        
        sensor.setFluidDensity(ms5837.DENSITY_SALTWATER)
    except Exception as e:
        # print_and_log("Could not connect to Pressure Sensor")
        logger.critical(e, exc_info=True)
        logger.critical("Could not connect to Pressure Sensor")
        sys.exit(1)
    

    #Define functions to get the depth, pressure and temperature from the pressure sensor
    def get_depth(retry:bool=False) -> float:
        try:
            sensor.read()
            depth : float = sensor.depth()
        except Exception as e:
            if retry:
                sleep(0.1)
                depth = get_depth()
            else:
                logger.exception(e)
                logger.error("Pressure Sensor Not Responding - setting depth to 0.0")
                # print_and_log("Pressure Sensor Not Responding - setting depth to 0.0")
                depth : float = 0.0
        return depth
    
    def get_pressure(retry:bool=False) -> float:
        try:
            sensor.read()
            pressure : float = sensor.pressure()
        except Exception as e:
            if retry:
                sleep(0.1)
                pressure = get_pressure()
            else:
                logger.exception(e)
                logger.error("Pressure Sensor Not Responding - setting pressure to 0.0")
                # print_and_log("Pressure Sensor Not Responding - setting pressure to 0.0")
                pressure : float = 0.0
        return pressure
      
      
    def get_temp(retry:bool=False) -> float:
        try:
            sensor.read()
            temp : float = sensor.temperature()
        except Exception as e:
            if retry:
                sleep(0.1)
                temp = get_temp()
            else:
                logger.exception(e)
                logger.error("Pressure Sensor Not Responding - setting temp to 0.0")
                # print_and_log("Pressure Sensor Not Responding - setting temp to 0.0")
                temp : float = 0.0
        return temp
    
    #Function to capture an image from the camera
    #This function is passed to the routine object and is called when the routine wants to capture an image
    #It takes an integration time in seconds, a gain value and a boolean for auto integration
    #If the integration time is 0 or None, the function will use auto integration
    def capture_image(integration_time_secs: float = None, gain: float = None, auto: bool = False, capture_n=None):
        """
        Capture an image using the specified integration time, gain, and auto-integration settings.

        Args:
            integration_time_secs (float, optional): Integration time in seconds. If set to 0 or None, auto-adjust integration time mode will be used. Defaults to None.
            gain (float, optional): Device gain value. If provided, the device gain will be changed to this value. Defaults to None.
            auto (bool, optional): Flag indicating whether to use auto-integration mode. If True, auto-integration mode will be used regardless of the integration time value. Defaults to False.

        Raises:
            Exception: If an error occurs while capturing the image.

        Returns:
            None
        """
        try:
            nonlocal current_session
            nonlocal current_routine

            integration_time = device.integration_time_seconds
            image_string = f"Capturing Image #{current_session.image_count + current_session.queue_length}(Routine image#{current_routine.image_count}) - Integration Time : {integration_time_secs}s"
            if auto:
                image_string += "- Auto Exposure"
            # print_and_log(image_string)

            logger.info(f"Capturing Image {current_session.image_count + current_session.queue_length} (#{current_routine.image_count} of routine)")
            logger.info(f"\tAuto integration time mode: {auto or integration_time_secs == 0 or integration_time_secs is None}")
            logger.info(f"\tIntegration Time: {integration_time_secs:8.5f}s")
            logger.info(f"\tGain: {gain}")

            if gain is not None:
                device.gain(gain)  # Change device gain if it is passed

            # Switch to auto-adjust integration time mode if integration time is 0 or None
            # Otherwise, set the integration time to the passed value.
            if integration_time_secs == 0 or integration_time_secs is None or auto:
                auto = True
            else:
                integration_time = device.integration_time(time=integration_time_secs, time_unit=device_interface.SECONDS)
                logger.info(f"\tSet integration time to {integration_time}")
                # print_and_log(f"Set Exposure Time to {integration_time}s")

            capture_successful = False
            image = None

            auto_attempt_no = 0
            auto_attempt_limit = 10

            # The device may have old images in the buffer with different integration times, 
            #so we need to set the desired integration time to the new value and it will flush the buffer until an image is captured with the new integration time.
            target_integration_time_us = convert_time(integration_time_secs, input_unit=device_interface.SECONDS, target_unit=device_interface.MICROSECONDS) if not auto else device.integration_time_microseconds 
            failed_captures = 0
            fail_limit = 5
            while not capture_successful: # Keep trying to capture an image until it is successful
                # print_and_log("Capturing...")
                logger.info("Initiating capture")
                image = device.capture_image(return_type=device_interface.CAM_IMAGE, target_integration_time_us=target_integration_time_us)
                if image is None: #Sometimes the camera fails to capture an image. If this happens, retry.
                    failed_captures += 1
                    # print_and_log("Capture failed - retrying...")
                    logger.warning(f"\tNo image captured - failed attempts:{failed_captures}/{fail_limit}")
                    

                    if failed_captures > 5:
                        err = Exception("Too many failed captures - skipping capture")
                        logging.exception(err, stack_info=True)
                        raise err
                    logger.warning('\tRetrying')
                    continue
                # print_and_log("Capture Complete")
                logger.info("\tCapture Complete")
                # Add the pressure, depth, and temperature to the image object and set whether it was an auto integration capture.
                image.set_depth(get_depth(retry=True))
                image.set_pressure(get_pressure(retry=True))
                image.set_environment_temperature(get_temp(retry=True))
                image.set_auto(auto)
                # Add the image to the session queue to be processed by the session thread
                current_session.add_image_to_queue(image)
                logger.info(f"\tAdded to Queue - Queue size: {current_session.queue_length}")
                # print_and_log(f"Added to Queue - Queue size: {current_session.queue_length}")
                # If in auto mode, check if the image has the correct saturation level and use the ids_interface.calculate_new_integration() function to calculate a new integration time if it does not.
                if auto:
                    # print_and_log("Auto")
                    auto_attempt_no += 1

                    sat_frac = get_fast_saturation_fraction(image, 250)
                    sat_min, sat_max = 0.005, 0.02
                    capture_successful = sat_frac > 0.005 and sat_frac < 0.02

                    # print_and_log("capture_successful: ", capture_successful)


                    if not capture_successful:
                        logger.warning(f"\tAuto capture unsuccessful ({auto_attempt_no}/{auto_attempt_limit} attempts)")
                        new_integration_time_s = device_interface.calculate_new_integration_time(
                            current_integration_time=image.integration_time_secs,
                            saturation_fraction=sat_frac)
                        logger.warning(f"\tAttempted integration time: {image.integration_time_secs} s")
                        logger.warning(f"\tIncorrect saturation fraction of {round(sat_frac, 3)}")
                        logger.warning(f"\tTarget is between {sat_min} and {sat_max}")
                        
                        # print_and_log(
                        #     f"Attempt {auto_attempt_no}: Incorrect saturation fraction of {round(sat_frac, 3)} - at {image.integration_time_us / 1e6}s - trying at {new_integration_time_s}s")
                        device.integration_time(time=new_integration_time_s, time_unit=device_interface.SECONDS)
                        logger.info(f"Reattempting at {new_integration_time_s} s")
                        integration_time = new_integration_time_s
                        target_integration_time_us = integration_time * 1e6
                    else:
                        # print_and_log(f"Attempt {auto_attempt_no}: Correct saturation at {image.integration_time_us / 1e6}s")
                        logger.info(f"\tAuto capture successful at {round(image.integration_time_secs, 5)}. ({auto_attempt_no} attempts)")
                        capture_successful = True
                else:
                    capture_successful = True

            logger.info(f"Captured Image #{current_routine.image_count}")
            logger.info(f"Timestamp: {image.time_string('%Y-%m-%d %H:%M:%S')}")
            logger.info(f"Integration Time: {image.integration_time_us / 1e6}s ")

        except Exception as e:
            logger.error(f"Error Capturing Image {current_routine.image_count}")
            logger.exception(e)
            # print_and_log(f"Error Capturing Image {current_routine.image_count}")
            
            # log_error(e)
        

   
    #Set the location of the routine files
    routine_dir=DATA_DIR / "routines"
    
    current_routine: routine.Routine = None
    
    #For each text or yml file in the routine directory check if it can be parsed as a Routine 
    #If it can and the name matches the passed in routine argument, set that as the routine to be used. 
    #When creating the routine, pass it the get_device_image function as its capture function.
    #Otherwise a dummy function is used which does not connect to the camera
    
    
    try:
        current_routine = routine.from_file(routine_name, capture_function=capture_image)
    except:
        for filename in os.listdir(routine_dir):
            if filename == routine_name:
                try:
                    current_routine = routine.from_file(Path(routine_dir) / filename, capture_function=capture_image)
                    break
                except Exception as e:
                    pass
                
            if filename.rsplit(".",1)[1].lower() in ["txt", "yaml", "yml"]:
                try:
                    this_routine = routine.from_file(Path(routine_dir) / filename, capture_function=capture_image)
                    if this_routine.name.replace(" ", "_") == routine_name.replace(" ", "_"):
                        current_routine = this_routine
                        break
                except Exception as e:
                    logger.warning(f"Routine file: {routine_dir}/{filename}")
                    logger.exception(e)

                    #print_and_log(f"Routine file: {routine_dir}/{filename}")
                    #log_error(e)
                    continue

    #If no matching routine can be found, log an error and exit
    if current_routine is None:
       
        logger.critical(f"Routine {routine_name} does not exist.\nMake sure routine name has no spaces\n Exiting.")
        #log_error(Exception(f"Routine {routine_name} not found"))
        #flush_stored_strings()
        sys.exit(1)
    



    #Set location of the session list file (It's in json format)
    session_list_file= DATA_DIR / "sessions" / "session_list.json"
    
    #Set empty variables to fill with session info
    session_path: Path = None
    current_session: session.Session = None  
    new_session = False
    session_dict:dict = None
    try:
        try:
            with open(session_list_file, mode="r") as session_list:
                #Open the session list and parse the json data into a dict object 
                session_dict = json.load(session_list)
                
                #Check if a session of the specified name is in the session list
                if session_name in session_dict:
                    #If it is get the session directory path and load the session from the file.
                    session_path = Path(session_dict[session_name]['directory_path']) / session_name.replace(" ", "_")
                    if session_path is not None and session_path.exists():
                        logger.info("Session Exists")
                        current_session = session.from_file(session_path)
                        current_session.log_info()
                else:
                    #If the session is not in the list, make a new session with that name. Session info such as coordinates/location
                    # will have to be added later in the console interface
                    logger.info(f"Session {session_name} not found")
                    logger.info("Creating new session...")
                    new_session = True
                    
        except:
            logger.info("Could not open Session List")
            logger.info("Starting new Session List")
            #print_and_log("Could not open Session List")
            new_session = True
            session_dict = {}
    
    
    
        #If a new session was created, add it to the session list file.
        if new_session:
            current_session = session.Session(name=session_name, directory=DATA_DIR / "sessions", log_queue=log_queue)
            
            logger.info(f"New Session Created in {current_session.parent_directory}")
            
    except Exception as e:
        logger.critical(f"Could not open session {session_name}")
        logger.critical(e, exc_info=True)
        logger.critical("Exiting...")
        # log_error(e)
        # flush_stored_strings()
        sys.exit(1)
  
  
  

            
    logger.info(f"Running routine {current_routine.name}...")
    logger.info(str(current_routine))
    
    #Run routine loop (see routine.py for more info on how this works)
    #The routine uses a "tick" system. 
    #
    # A while loop is started, and on each "tick" the object checks the time since the routine 
    # started and when the next capture should be to automatically capture photos
    # using the settings defined in the routine file.
    # It adds the capture settings to a queue which is processed by a separate thread.
    # Each capture is added to the session queue with a timestamp and other data, including the pressure, temperature, etc. 
    # Another thread defined in the sessions.py file processes the queue and saves the images to the session directory.
    # The routine will continue to tick until the routine is complete or a stop signal is received.
    # The stop signal can be sent from the console interface using runcam -x.
    # The routine will then finish the current capture and stop.
    # The session thread will finish processing the queue and save the images.

    #The program uses Named Pipes to communicate with the console interface. This allows the interface to send a stop signal to the script, 
    #and for the script to send messages back to the interface allowing the user to view the progress of the current capture routine using "runcam -q"
    # or "runcam -l" to view the live output log.
    

    if not os.path.exists(PIPE_IN_FILE):
        os.mkfifo(PIPE_IN_FILE)
        
    if not os.path.exists(PIPE_OUT_FILE):
        os.mkfifo(PIPE_OUT_FILE)
    
    #Set the camera to continuous acquisition mode and turn off auto integration and gain
    device.gain(1)
    device.change_sensor_mode(device_interface.DEFAULT)
    device.integration_time(time=current_routine.int_times_seconds[0], time_unit=device_interface.SECONDS)
    
    device.start_acquisition(mode=device_interface.CONTINUOUS)
    
    device.set_to_manual()
    
    sleep(0.5)

    complete = False

    #Set up variables for checking the time and the number of consecutive errors
    consecutive_error_count = 0


    in_pipe_fd = os.open(PIPE_IN_FILE, os.O_RDONLY | os.O_NONBLOCK)
      
    
    def write_to_pipe(message:str):
        """
        Writes a message to a named pipe for communication with the console interface.

        Args:
            message (str): The message to be written to the named pipe.

        Raises:
            OSError: If there is an error opening or closing the named pipe.
            Exception: If there is an error passing the message to the named pipe.

        Returns:
            None
        """
        try:
            out_pipe_fd = os.open(PIPE_OUT_FILE, os.O_WRONLY | os.O_NONBLOCK)
            with os.fdopen(out_pipe_fd, "w") as out_pipe:
                out_pipe.write(message)
            os.close(out_pipe_fd)  
            logger.info("Successfully passed message " + message)
        except OSError:
            pass
        except Exception as e:
            logger.error("Error passing message to named pipe")
            logger.exception(e)
    
    # set the time variables to the current time. The loop and run any code in intervals of long_check_length and short_check_length
    check_time_long = time()
    long_check_length = 300
    check_time_short = time()
    short_check_length = 1
    
    #Start the session thread to process the queue
    current_session.start_processing_queue()

    #Main loop
    with os.fdopen(in_pipe_fd) as in_pipe: #Open the named pipe for reading
        in_pipe.read()
        while not complete: #Loop until the routine is complete or a stop signal is received
            try:

                # Check for stop message
                message = in_pipe.read()
                if message:
                    
                    if message == "STOP":
                        logger.info("Received STOP Message")
                        current_routine.stop_signal.set()
                        current_routine.end_capture_thread()
                        if current_routine.capturing_images.is_set():
                            logger.info("Waiting for image capture to finish...")
                        else: 
                            logger.info("Stopping")
                        for i in range(10):
                            write_to_pipe("STOPPING")
                            sleep(0.2)
                    else:
                        logger.info(f"Received Message: {message}")
                        
                        

                
                if not current_routine.stop_signal.is_set():   
                    if time() - check_time_long > long_check_length:
                        logger.info(f"Runtime: {str(timedelta(seconds=int(current_routine.run_time)))} Device Temp: {device.temperature}°C  Depth: {get_depth():.2f}m Pressure Sensor Temp: {get_temp():.2f}°C")
                        check_time_long = time()

    
                if time() - check_time_short > short_check_length:
                    check_time_short = time()
                    try:
                        message = f"Routine: {current_routine.name}\nSession: {current_session.name_no_spaces}\nRuntime: {str(timedelta(seconds=int(current_routine.run_time)))}\nImages Captured: {current_routine.image_count}\nImage Save Queue Size: {current_session.queue_length}\n"
                        if current_routine.stop_signal.is_set():
                            message  += "\nSTOPPING\n"
                        write_to_pipe(message)
                    except Exception as e:
                        pass

                #current_session.run_and_log(current_routine.tick)
                current_routine.tick()
                
                
                
                complete = current_routine.complete.is_set()
                consecutive_error_count = 0
                
                
                
            except Exception as e:
                logger.warning("Tick Error")
                logger.exception(e)

                consecutive_error_count += 1
                
                logger.warning(f"Error count: {consecutive_error_count}")
                if consecutive_error_count > 5:
                    logger.critical("AEGIR: Too many consecutive tick errors. Exiting")
                    
                    sys.exit(1)
    logger.info(f"Completion Reason: {current_routine.stop_reason}")
    device.stop_acquisition()
    current_routine.complete.wait()
    current_session.stop_processing_queue()
    logger.info(f"Complete at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")


#Wrapper code for running this script.
#Exits with exit code 0 if completed successfully, or 1 if there is an unhandled exception.
if __name__ == '__main__':
    try:


        root = logging.getLogger()
        root.setLevel(logging.DEBUG)

        log_queue = queue.Queue()



        file_handler= logging.FileHandler("aegir.log")
        file_handler.setLevel(logging.DEBUG)
        
        queue_handler = logging.handlers.QueueHandler(log_queue)

        critical_handler = logging.StreamHandler(sys.stderr)
        critical_handler.setLevel(logging.CRITICAL)

        formatter = logging.Formatter(fmt='%(asctime)s.%(msecs)03d - %(module)16s - %(levelname)8s - %(message)s', datefmt="%Y-%m-%d %H:%M:%S")

        file_handler.setFormatter(formatter)
        queue_handler.setFormatter(formatter)
        critical_handler.setFormatter(formatter)

        root.addHandler(file_handler)
        root.addHandler(queue_handler)
        root.addHandler(critical_handler)
        main(log_queue)
        sys.exit(0)
    except argparse.ArgumentError as e:
        # Print the provided arguments if there is an error
        print(f'Error parsing command line arguments: {e.argument_name}')
        print(e)
        sys.exit(1)
    except Exception as e:
        traceback.print_exception(e)
        sys.exit(1)