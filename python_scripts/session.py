import logging.handlers
from pathlib import Path
import json
import cam_image
import sys, os
from dotenv import load_dotenv
import traceback
import threading, queue
import logging
from datetime import datetime


logger = logging.getLogger()

#Load environment variables
dot_env_path = Path(__file__).parent.parent / ".env"
load_dotenv(dotenv_path=dot_env_path)

DATA_DIR =  Path(os.environ.get("DATA_DIRECTORY"))
PRETTY_FORMAT = "%Y-%m-%d %H:%M:%S"
FILEPATH_FORMAT = "%Y_%m_%d__%H_%M_%S"
class Session:
    
    def __init__(self, name:str|None=None, start_time:datetime|None = None, directory:str|None=None, images:dict=None, log_queue:queue.Queue=None) -> None:
        try:
            
            if start_time is None:
                self.start_time:datetime = datetime.now()
            else:
                self.start_time = start_time 
            
            
            if name is None or name == "":
                self.name:str = f"{self.start_time_string(FILEPATH_FORMAT)}"
            else:
                self.name:str = name.strip()
                
            self.name_no_spaces = self.name.replace(" ", "_")
                

                
            if directory is None:
                self.parent_directory :Path =DATA_DIR / "sessions"
            else:
                self.parent_directory :Path = Path(directory)
                
            self.directory = self.parent_directory / self.name_no_spaces
            self.image_directory = self.directory / "images"
            self.csv_file_path = self.directory / "data.csv"
            self.json_file_path = self.directory / "session.json"
            self.output_file_path = self.directory / "output.log"
            self.session_list_file = self.parent_directory / "session_list.json"
            
            self.image_directory.mkdir(parents=True, exist_ok=True)
            self.processing_queue = threading.Event()
            self.queue_shutdown = threading.Event()
            self.finished_processing = threading.Event()
            self.images:list[dict]=[]
            
            if images is None:
                self.last_updated = self.start_time
            else:
                self.images = images
                self.last_updated = datetime.strptime(self.images[-1]['time'], PRETTY_FORMAT)
                
                    
            self.log_queue = log_queue if log_queue is not None else queue.Queue()
            file_handler = logging.FileHandler(self.output_file_path)
            file_handler.setLevel(logging.DEBUG)

            #logging_formatter = logging.Formatter('%(message)s')

            #file_handler.setFormatter(logging_formatter)

            self.logging_queue_listener = logging.handlers.QueueListener(self.log_queue, file_handler, respect_handler_level=True)

            self.logging_queue_listener.start()

            self.update_session_list()  
            self.write_to_log()
            
            self.image_queue:queue.Queue = queue.Queue(maxsize=8) 
            
            
        except Exception as e:
            logger.critical("Error initiating session", exc_info=True)
            # traceback.print_exception(e, file=sys.stderr)
            raise e
    
    @property
    def details(self) -> dict:
        return {"name" : self.name,
                    "start_time" : self.start_time.strftime(PRETTY_FORMAT),
                    "last_updated": self.last_updated.strftime(PRETTY_FORMAT),
                    "path" : str(self.directory),
                    "image_count" : self.image_count
                    }
    
    
    @property
    def queue_length(self) -> int:
        return self.image_queue.qsize()
    
    @property
    def last_image(self) -> dict|None:
        if self.images is not None:
            return self.images[-1]
        else:
            return None
    
    def start_time_string(self, format:str="%Y-%m-%d %H:%M:%S") -> str:
        return datetime.strftime(self.start_time, format)
    
    def add_image(self, image:cam_image.Cam_Image)-> cam_image.Cam_Image:
        image.set_number(self.image_count)
        self.images.append(image.info)
        return image
    
    @property
    def image_count(self) -> int:
        if self.images is not None:
            return len(self.images)
    
    def add_image_to_queue(self, image:cam_image.Cam_Image|None):
        
        if image is None:
            logger.info("Adding sentinel value to processing queue")
        else:
            logger.info("Adding image to queue")
        if self.queue_shutdown.is_set():
            logger.error("Processing queue is closed. Item not added.")
        else:
            self.image_queue.put(image)
        logger.info(f"Processing queue length: {self.queue_length}")
            
    def start_processing_queue(self):
        logger.info("Starting processing queue")
        process_thread = threading.Thread(target=self.process_image_queue)
        process_thread.daemon = True
        self.queue_shutdown.clear()
        self.processing_queue.set()
        self.finished_processing.clear()
        process_thread.start()
        
    def stop_processing_queue(self):
        self.add_image_to_queue(None)
        self.queue_shutdown.set()
        logging.info("Waiting to process remaining images")
        self.finished_processing.wait()
        logging.info("Finished processing last image")
    
    def process_image_queue(self) -> bool:
        while True:
            image = self.image_queue.get()
            
            if image is None:

                logging.info("Processing queue: Sentinel value received")
                self.image_queue.task_done()
                if not self.image_queue.empty():
                    logging.error("Processing queue: Sentinel value received but queue is not empty")
                break
            try:
                image = self.add_image(image)
                logger.info(f"Processing image {image.number} - Queue size {self.queue_length}")
                # self.output(f"Processing image {image.number} - Queue size {self.queue_length}")
            except Exception as e:
                logger.error("Couldn't add image to session.images")
                logger.exception(e, stack_info=True)
                # self.output("Warning: couldn't add image to session.images", error=True)
                # self.output(traceback.format_exception(e), error=True)
            
            try:
                self.update_session_list()
            except Exception as e:
                # self.output("Warning: couldn't update session_list", error=True)
                # self.output(traceback.format_exception(e), error=True)
                logger.error("Couldn't update session_list")
                logger.exception(e, stack_info=True)
                                            
            
            try:        
                image_location = self.image_directory/ f"{self.name_no_spaces}_{str(image.number).rjust(3, '0')}.png"
                
                image.save(image_location, additional_metadata={"session" : self.name})
            except Exception as e:
                logger.error(f"Couldn't save image {self.image_count-1}")
                logger.exception(e, stack_info=True)
                # self.output(f"Warning: couldn't save image {self.image_count-1}", error=True)
                # self.output(traceback.format_exception(e), error=True)
                                            
            try:    
                self.write_to_log()
            except Exception as e:
            #     self.output("Warning: couldn't write to meta file", error=True)
            #     self.output(traceback.format_exception(e), error=True)
                logger.error(f"Couldn't write to meta file")
                logger.exception(e, stack_info=True)
            try:                                
                self.write_to_csv(image)
            except Exception as e:
                # self.output("Warning: couldn't add image details to csv", error=True)
                # self.output(traceback.format_exception(e), error=True)
                logger.error(f"Couldn't add image details to csv")
                logger.exception(e, stack_info=True)                
            logging.info(f"Finished processing image {image.number} - Queue size {self.queue_length}")
            self.image_queue.task_done()   

        logging.info("Processing queue: Exited processing loop.")
        self.processing_queue.clear()
        self.finished_processing.set()

    def write_to_log(self) -> bool:
            log = self.details
            log["images"] = self.images
            return write_json(log, self.json_file_path)

    def write_to_csv(self, image:cam_image.Cam_Image) -> bool:
            with open(self.csv_file_path, "a") as csv_file:
                if csv_file.tell() == 0:
                    csv_file.write(",".join(list(image.info.keys())) + "\n")
                csv_file.write(",".join([str(value) for value in list(image.info.values())]) + "\n")
        

    def update_session_list(self):
        session_list = {}
        if self.session_list_file.exists():
            try:
                with open(self.session_list_file, "r") as session_list_file:
                    session_list = json.load(session_list_file)
            except:
                session_list = {}
        
        session_list[self.name] = self.details
        with open(self.session_list_file, "w") as session_list_file:
            json.dump(session_list, session_list_file, ensure_ascii=False, indent=5)
    
    
    def output(self, output:str|list, error:bool=False) -> bool:
        try:
            if not isinstance(output, (list, tuple)):
                output = [[ output, datetime.now()],]
            try:    
                if isinstance(output[-1], str):
                    output = [["".join(output), datetime.now()],]
            except:
                pass
            if error:
                for string, timestamp in output:
                    print(f"{timestamp.strftime(PRETTY_FORMAT)}: {string}", file=sys.stderr)
            
            with open(self.output_file_path, "a") as session_output_file:
                for string, timestamp in output:
                    session_output_file.write(f"{timestamp.strftime(PRETTY_FORMAT)}: {string}\n")
                        
            return True
        except Exception as e:
            traceback.print_exception(e, file=sys.stderr)
            return False
    
        
    def print_info(self):
        print("Session Info")
        for key, value in self.details.items():
            print(f"{key.rjust(18)}: {value}") 

    def log_info(self):
        logger.info(f"Session '{self.name}' info:")
        for key, value in self.details.items():
            logger.info(f"{key.rjust(18)}: {value}")      
         
    def __str__(self):
        string = ""
        for key, value in self.details.items():
            if string != "":
                string += "\n"
            string += f"{key.rjust(18)}: {value}"   
        return self.name         
    
    def __getitem__(self, image_number:int) -> dict:
        return self.images[image_number]
    
    def __iter__(self):
        return iter(self.images)
    
    def __len__(self):
        return len(self.images)
      
def write_json(log:dict, filepath:Path) -> bool:
    with open(filepath, "w") as session_log_file:
        json.dump(log, session_log_file, indent=5, ensure_ascii=False)
                    
    return True


def from_file(path:str|Path) -> Session:
    """Open Session:
        Open a session from a log file

    Args:
        log_file (str): path to log session

    Returns:
        Session: A session object with details matching those in log file
    """    
    try:
        log_file = Path(path) / "session.json"
        if not log_file.exists():
            logger.warning(f"Session file {log_file} does not exist")
            return None
        
        session_dict = {}
        with open(log_file, mode="r") as file:
            session_dict = json.load(file)
        
        name = session_dict["name"]
        start_time = datetime.strptime(session_dict["start_time"], "%Y-%m-%d %H:%M:%S")

        path = session_dict["path"]
        session = Session(name=name, start_time=start_time, directory=path, images=session_dict['images'])
        
        
        return session
    
    
    except Exception as e:
        logger.exception("Error loading session from file")
        return None
    
