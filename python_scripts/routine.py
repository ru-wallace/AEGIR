#TODO: Add field for limit for number of auto-adjust attempts

import time
from datetime import datetime, timedelta
from pathlib import Path
import numpy as np
import threading
import queue
import logging

CAPTURE_START = "capture_start"
CAPTURE_END="capture_end"
ACCEPTED_PARAMS={"name":str, "initial_delay_time_secs":(float,int), "number_limit":(float,int),
                 "time_limit_secs":(float,int), "repeat":(float, int), "repeat_interval_time_secs":(float,int), "interval_mode":str,
                 "interval_secs":(float,int), "integration_time_secs":(float,int),
                 "loop_integration_time":bool, "gain":(float,int), "loop_gain":bool,
                 "min_tick_length_secs":(float,int), "all_combinations":bool}


logger = logging.getLogger()


class Routine:
    
    def placeholder_capture(integration_time, gain, auto, capture_n=None):
        int_string = f"{round(integration_time, 6)}s"
        if integration_time == 0 or auto:
            int_string = "Auto-adjust"
        
        
        logger.info(f"Routine Module Placeholder capture function called")
        logger.info(f"\t{capture_n}: Exposure time: {int_string} | gain: {gain}")   
        time.sleep(integration_time)
        logger.info(f"\tPlaceholder capture function complete")
    
        return None

    def __init__(self, name,
                 initial_delay_time_secs:float=0, 
                 number_limit:int|float=10000,
                 time_limit_secs:float=255*60*60,
                 repeat:int|float = 1,
                 repeat_interval_time_secs:float=0,
                 interval_mode:str=CAPTURE_END, 
                 interval_time_secs:float=0,
                 integration_time_secs:float|list=0, 
                 loop_integration_time:bool=False,
                 gain:float|list=1, 
                 loop_gain:bool=False,
                 all_combinations:bool=False,
                 min_tick_length_secs:float=0.01,
                 capture_function:callable=placeholder_capture) -> None:

        
        
        self.name:str = name
        
        self.initial_delay:float=initial_delay_time_secs
        self.number_limit:int = min(int(number_limit), 10000) #max images is 10000
        
        self.time_limit_secs:float = min(time_limit_secs, 255*60*60) #maximum time is 255 hours 
        self.repeat:int = int(repeat)
        self.repeat_interval_time_secs:float = repeat_interval_time_secs
        
        settings = Routine._create_settings_matrix(integration_times=integration_time_secs,
                                                       gains=gain,
                                                       all_combinations=all_combinations,
                                                       number_limit=self.number_limit,
                                                       loop_gain=loop_gain,
                                                       loop_integration_time=loop_integration_time)
        
        self.iteration_length = np.size(settings[0,:])
        
        if self.repeat == 0:
            self.repeat = int(self.number_limit / self.iteration_length)
        
        
        settings = np.tile(settings, self.repeat)

        
        self.int_times_seconds:np.ndarray = settings[0,:self.number_limit]
        self.gains:np.ndarray = settings[1,:self.number_limit]
        
        #Create queue which holds the settings for each photo.
        self.params_queue : queue.Queue = queue.Queue()
        for param_set in range(self.int_times_seconds.shape[0]):
            self.params_queue.put({'integration_time': self.int_times_seconds[param_set],
                                   'gain': self.gains[param_set]})
        
        # Add a None value to the end of the queue. When this is reached, the image acquisition thread will stop
        self.params_queue.put(None)


                
        if interval_mode.lower() not in [CAPTURE_START, CAPTURE_END]:
            logger.warning("Interval mode not recognised, setting to default: CAPTURE_START ")
            interval_mode = CAPTURE_START
        self.interval_mode=interval_mode
        
        self.interval_secs = interval_time_secs
        
        capture_start = self.interval_mode == CAPTURE_START
        capture_end = self.interval_mode == CAPTURE_END
        self.expected_time = self.int_times_seconds.size +sum(self.int_times_seconds) + self.repeat*self.repeat_interval_time_secs + capture_start*self.interval_secs*self.int_times_seconds[self.int_times_seconds > self.interval_secs -1].size + capture_end*self.interval_secs*self.int_times_seconds.size
        self.expected_time = int(min(self.time_limit_secs, self.expected_time))
        
        
        self.tick_length = min(min_tick_length_secs, 0.001)
        #Variables for running
        self.capture_function = capture_function
        self.start_time = None
        self.run_time = 0
        self.next_capture = None
        self.image_count = 0
        self.complete = threading.Event()
        self.last_time_printed=0
        self.capturing_images=threading.Event()
        self.stop_signal = threading.Event()
        self.stop_reason = None
        self.capture_queue :queue.Queue = queue.Queue()
        self.capture_start_time = None
        
    def __str__(self):
        string = ""
        string += f"Routine: {self.name}"
        string += f"\nInitial delay: {self.initial_delay}s"
        string += f"\nNumber Limit: {self.number_limit}"
        string += f"\nTime Limit: {str(timedelta(seconds=self.time_limit_secs))}"
        string += f"\nInterval: {self.interval_secs}s"
        string += f"\nInterval Mode: {self.interval_mode}"
        string += f"\nIteration Length: {self.iteration_length}"
        string += f"\nRepeat: {self.repeat}"
        string += f"\nRepeat Interval: {self.repeat_interval_time_secs}s"
        string += f"\nIntegration_times (s): { (str(self.int_times_seconds[:7]).strip(']') + '...]') if len(str(self.int_times_seconds)) > 10 else str(self.int_times_seconds)}"
        string += f"\nGain settings: { (str(self.gains[:7]).strip(']') + '...]') if len(str(self.gains)) > 10 else str(self.gains)}"
        string += f"\nPlanned Image total: {self.int_times_seconds.size}"
        string += f"\nTime Estimate: {datetime.fromtimestamp(time.time() + self.expected_time).strftime('%Y-%m-%d %H:%M:%S')} ({str(timedelta(seconds=self.expected_time))})"
        string += f"\nTick length: {self.tick_length}"
        return string
    
    def log_routine_info(self):
        for line in str(self).splitlines():
            logger.info(line)


    
    def start_capture_thread(self):
        capture_thread = threading.Thread(target=self.process_capture_queue)
        capture_thread.daemon=True
        capture_thread.start()
        logger.info("Started capture thread")
      
    def end_capture_thread(self):
        logger.info("Stopping capture thread")
        if not self.capturing_images.is_set():
            logger.info("Capture thread already stopped")
            return      
        self.capture_queue.put(None)
        logger.info("Added sentinel value to capture queue.")
        self.capturing_images.wait()
        logger.info("Capture thread completed")
        
    def process_capture_queue(self):
        try:
            self.capturing_images.set()
            while True:
                if self.stop_signal.is_set():
                    logger.info("Capture Queue: Stop signal received.")
                if self.complete.is_set():
                    logger.info("Capture Queue: Complete before next item retrieved.")
                    break
                image_params = self.capture_queue.get()
                try:
                    if image_params is None:
                        logger.info("Capture Queue: Sentinel value received.")
                        self.complete.set()
                        break
                    integration_time = image_params["integration_time"]
                    gain=image_params["gain"]
                    self.capture_image(integration_time=integration_time, gain=gain)
                    
                except Exception as e:
                    logger.exception("Error processing capture queue item")
                    #traceback.print_exception(e, file=sys.stderr)
                finally:
                    self.capture_queue.task_done()
        except Exception as e:
            logger.exception("Error processing capture queue")

        finally:                
            self.capturing_images.clear()
            self.complete.set()
            logger.info("Capture Queue: Finished processing capture queue.")
            return

    def capture_image(self, integration_time, gain):
        try:
            self.capture_start_time = time.time()
            if self.interval_mode == CAPTURE_START:
                self.set_next_capture_time()
               
            auto = False
            int_string = str(integration_time)+'s'
            if integration_time == 0:
                auto = True
                int_string = "Auto"
            
            logger.info(f"Routine Module: {round(time.time()-self.start_time, 2)}s ==> Capturing Img #{self.image_count} ~ I:{int_string} | G: {gain}dB")

                    
            self.capture_function(integration_time_secs=integration_time, gain=gain, auto=auto, capture_n = self.image_count+1)
            self.image_count += 1
            if self.interval_mode == CAPTURE_END: 
                self.set_next_capture_time()
        except Exception as e:
            logger.error(f"Error capturing image {self.image_count}")
            logger.exception(e)

    def set_next_capture_time(self):

        #if self.interval_mode == CAPTURE_END:

        self.next_capture = time.time()+self.interval_secs
        #else:
        #    self.next_capture = self.capture_start_time + self.interval_secs
        image_count = self.image_count if self.interval_mode == CAPTURE_END else self.image_count + 1
        if image_count % self.iteration_length == 0:
            self.next_capture = time.time() + self.repeat_interval_time_secs
        logger.info(f"Set next capture time to: {datetime.fromtimestamp(self.next_capture).strftime('%Y-%m-%d %H:%M:%S')}")
        
    def tick(self):
        self.now = time.time()
        if self.start_time is None:
                logger.info(f"Starting routine {self.name}")
                self.start_capture_thread()
                self.start_time = time.time()

                self.next_capture =  self.start_time + self.initial_delay
        try:
            
            self.run_time = self.now-self.start_time
            
            def tick_done(complete:bool=False, stop_reason:str=None):
                if complete:
                    self.complete.set()
                tick_remaining = self.tick_length-(time.time()-self.now)

                if (complete or self.stop_signal.is_set()) and stop_reason is not None and self.stop_reason is None:
                    self.stop_reason = stop_reason
                
                if self.stop_signal.is_set() or self.complete.is_set():
                    self.capture_queue.put(None)

                if complete:
                    logger.info(f"Tick Done: Stop Signal:{self.stop_signal.is_set()} Complete:{self.complete.is_set()}")
                    logger.info(f"Stop Reason: {self.stop_reason}")
                    
                
                if tick_remaining > 0:
                    time.sleep(tick_remaining)
                return self.complete.is_set()
            
            if self.complete.is_set():
                 tick_done(True, "Complete at start of tick - maybe externally changed")
                 return self.complete.is_set()
            if self.stop_signal.is_set():
                if not self.capturing_images.is_set():
                    self.complete.set()
                tick_done(self.complete.is_set(), "Received Stop Signal")
                return self.complete.is_set()
                
            

            if self.number_limit is not None:
                if self.image_count >= self.number_limit:
                    if self.capturing_images.is_set():
                        self.stop_signal.set()
                    else:
                        self.complete.set()
                    tick_done(self.complete.is_set(), f"Reached Number Limit of {self.number_limit} (Image count: {self.image_count}, Number of integration_times: {self.int_times_seconds.size}) (First trap)")
                    return self.complete.is_set()
            
            
            if self.time_limit_secs is not None:
                if self.run_time >= self.time_limit_secs:
                    self.stop_signal.set()
                    tick_done(self.complete.is_set(), "Time Limit Reached")
                    return self.complete.is_set()
            
            
            if self.image_count >= self.int_times_seconds.size:
                if not self.capturing_images.is_set():
                    self.complete.set()
                else:
                    self.stop_signal.set()
                tick_done(self.complete.is_set(), f"Reached end of routine ({self.image_count}/{self.int_times_seconds.size} images)")
                return self.complete.is_set()
            
            if self.now > self.next_capture and not self.stop_signal.is_set():
                self.next_capture = self.next_capture + 10000000
                next_param_set = self.params_queue.get(block=False)
                if next_param_set is None:
                    self.complete.set()
                    tick_done(self.complete.is_set(), f"Reached end of routine ({self.image_count}/{self.int_times_seconds.size} images)")
                else:
                    self.capture_queue.put(next_param_set)
                self.params_queue.task_done()
                return self.complete.is_set()
            

                
            tick_done(self.complete.is_set(), "End of Tick")

        except Exception as e:
            #traceback.print_exception(e)
            logger.error("Tick Error")
            logger.exception(e)
            tick_done(self.complete.is_set(), "Error")
        return self.complete.is_set()
    

    
    def _create_settings_matrix(integration_times, gains, all_combinations, number_limit, loop_integration_time, loop_gain):
        integration_times = np.array(integration_times)
        gains = np.array(gains)
        settings = None
        
        # if all_combinations is TRUE, create a setting array of all possible unique combinations of gain and
        # integration times 
        if all_combinations:
            #reduce integration times and gain to just unique values
            integration_times =  integration_times[np.sort(np.unique(integration_times, return_index=True)[1])]
            gains = gains[np.sort(np.unique(gains, return_index=True)[1])]
            
            settings = np.array(np.meshgrid(integration_times, gains)).reshape(2,-1)
        
            return settings
        

        #If either gain or integration time are a single value, extend them out into an array
        # as long as the other, or as long as the number limit if both are single value
        if integration_times.size == 1:
            if gains.size > 1:
                integration_times = np.full(gains.size, integration_times)
            else:
                integration_times = np.full(number_limit, integration_times)

        if gains.size == 1:
            gains = np.full(integration_times.size, gains)

        
        #if gain or integ time is longer than the other, cut it down to the shorter length
        # or, if loop is TRUE for the shorter, extend it to the longer length by repeating it
        if gains.size < integration_times.size:
            if loop_gain:
                gains.resize(integration_times.size)
            else:
                integration_times = integration_times[:gains.size]
        elif gains.size > integration_times.size:
            if loop_integration_time:
                integration_times.resize(gains.size)
            else: 
                gains = gains[:integration_times.size]     
        
        #Stack integration times and gain arrays in the shape:
        #                           0  1  2  3
        # integration times --> 0 [[1, 2, 3, 4],
        #       gain values --> 1 [5, 6, 7, 8]]
        
        # i.e to access a gain value for a given index, use settings[1,[index]]
        # and for integration times, use settings[0,[index]]
        settings:np.ndarray = np.vstack([integration_times, gains])
        
        
        return settings


    
def convert(val:str)-> float|str|bool: #try to convert value to the correct datatype
    val = val.strip()
    try:    #try to convert to float, leave as string if not
        val = float(val)
        return val
    except Exception as e:
        pass
    if val.lower() in ["true", "t", "yes", "y"]: #convert to boolean if possible
        val = True
    elif val.lower() in ["false", "f", "no", "n"]:
        val = False
    
    return val
    
def parse_value(value:str) -> str|list|float|bool:
    value = value.strip()
    if value.startswith("["):
        if not value.endswith("]"):
            return None
        list_type = None
        val_list = []
        for item in value.strip(" []").split(","):
            item = item.strip()
            item = convert(item)
            if list_type is None: #for first item, set type of list to what that item is
                list_type = type(item)
            else:
                if type(item) != list_type: #check the type of item matches the list 
                    return None
            val_list.append(item)
        return val_list
    

    
    value = convert(value)
    

    return value            
        
                
        
    
def parse_line(line:str) -> dict:
        try:
            line = line.strip()
            if line.startswith("#") or line == "" or ":" not in line:
                return None
            line = line.split(" #", 1)[0] #remove inline comments
            parameter, value = line.split(":")
            parameter = parameter.strip().lower()
            value = value.strip()
            parameter = parameter.replace(" ", "_")
            
            value = parse_value(value)
            return (parameter, value)
        except Exception as e:
            logger.exception(f"Error processing Line: {line}")


            return None
        
def convert_to_seconds(value:int|float, unit:str)->float:
    unit = unit.lower()
    multiplier = None
    match unit:
        case h if h in ["hours", "hour", "hrs", "hr", "hs", "h"]:
            multiplier = 60*60
        case m if m in ["minutes", "minute", "mins", "min", "m"]:
            multiplier = 60
        case s if s in ["seconds", "second", "sec", "secs", "s"]:
            multiplier = 1
        case ms if ms in ["milliseconds", "millisecond", "ms"]:
            multiplier = 1/1000
        case us if us in ["microseconds", "microsecond", "us"]:
            multiplier = (1/1000)/1000
        case _:
            multiplier = 1
    
    try:
        result = [item*multiplier for item in value]
    except TypeError:
        result =value*multiplier
    return result

def from_dict(params:dict, capture_function:callable=Routine.placeholder_capture) -> Routine:
    
    valid_params = {}

    units = {"default_time_unit":"s",
             "time_limit_unit":None, 
             "initial_delay_time_unit":None,
             "interval_time_unit":None,
             "repeat_interval_time_unit":None,
             "integration_time_unit":None,
             "min_tick_length_unit":None}
    
    times = {"time_limit":None,
             "initial_delay_time":None,
             "repeat_interval_time":None,
             "interval_time":None,
             "integration_time":None,
             "min_tick_length":None}
    for key, value in params.items():
        
        valid=key in ACCEPTED_PARAMS and isinstance(value, ACCEPTED_PARAMS[key])
        if valid:
            if key in valid_params: #If the parameter is already set, notify and update
                #Create short string representing value to print if value is longer than 10 chars
                val_string =  (str(value[:7]) + '...') if len(str[value]) > 10 else str[value]
                valid_params[key] = value
            else:
                valid_params.update([(key, value)])
            continue
        
        #Find parameters for setting times and time units
        match key: 
            case unit_param if unit_param in units:
                units[key] = value
            case time_param if time_param in times:
                times[key] = value
    

    for param, value in times.items(): #convert any time parameters to seconds
        if value is not None:          #by getting the unit it is currently in
            unit = units[f"{param}_unit"] #and multiplying to convert
            if unit is None:
                unit = units["default_time_unit"]
            
            time_in_secs = convert_to_seconds(value, unit)
            valid_params.update([(f"{param}_secs", time_in_secs)])
            
    return Routine(capture_function=capture_function, **valid_params)
    
        
        
def from_file(file_path:str|Path, capture_function:callable=Routine.placeholder_capture) -> Routine:
            lines = []
            with open(file_path, mode="r") as file:
                   lines = file.readlines()  
                   
            
            params = {}
            for line in lines:
                parsed_line = parse_line(line)
                if parsed_line is not None:
                    params.update([parsed_line])
                
            return from_dict(params, capture_function=capture_function)
                

        
        

