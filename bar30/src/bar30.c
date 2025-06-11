#include "ms5837.h"
#include "bar30.h"

#include <pigpiod_if2.h>
// #include <signal.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#include <math.h>






//kg/m^3 convenience
int DENSITY_FRESHWATER = 997;
int DENSITY_SALTWATER = 1029;

// Conversion factors (from native unit, mbar)
float UNITS_Pa     = 100.0;
float UNITS_hPa    = 1.0;
float UNITS_kPa    = 0.1;
float UNITS_mbar   = 1.0;
float UNITS_bar    = 0.001;
float UNITS_atm    = 0.000986923;
float UNITS_Torr   = 0.750062;
float UNITS_psi    = 0.014503773773022;


float ALTITUDE_COEFFICIENT = 44330.0f; // Altitude coefficient for Pa to meters conversion
float ALTITUDE_BASE_PRESSURE_PA = 101325.0f; // Base pressure at sea level in Pa
float ALTITUDE_EXPONENT = 0.190284f; // Exponent for altitude calculations

float GRAVITY_ACCELERATION = 9.80665f; // Standard gravity in m/s^2

// I2C read and write functions to pass as callbacks to the sensor library
void bar30_i2c_read(int16_t pigpiod_instance_handle, uint16_t i2c_bus, uint8_t address, uint8_t command, uint8_t *data, uint8_t num_bytes );
void bar30_i2c_write(int16_t pigpiod_instance_handle, uint16_t i2c_bus, uint8_t address, uint8_t command, uint8_t*, uint8_t);



int bar30_init(bar30_t *bar30_instance, uint16_t i2c_bus, bool verbose)
{
    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return 1; // Initialization failed
    }



    if (verbose)
    {
        printf("Initializing BAR30 sensor on I2C bus %d\n", i2c_bus);

    }
    // Initialize the sensor object
    ms5837_t bar30_sensor = { .i2c_bus=i2c_bus };

    bar30_instance->sensor = bar30_sensor; // Assign the sensor object to the instance

    bar30_instance->sensor.pigpiod_instance_handle = pigpio_start(NULL, NULL); // Connect to pigpio daemon


    if (bar30_instance->sensor.pigpiod_instance_handle < 0)
    {
        printf("Failed to connect to pigpio daemon.\n");
        printf("Ensure the pigpio daemon is running.\n");
        printf("You can start it with: sudo pigpiod\n");
        char *error_message = pigpio_error(bar30_instance->sensor.pigpiod_instance_handle);
        printf("Error %d: %s\n", bar30_instance->sensor.pigpiod_instance_handle, error_message);
        return 1;
    }
    ms5837_i2c_set_read_fn( &bar30_instance->sensor, bar30_i2c_read );
    ms5837_i2c_set_write_fn( &bar30_instance->sensor, bar30_i2c_write );
    // Initialize the sensor
    ms5837_reset(&bar30_instance->sensor);
    
    // Read calibration data
    if (!ms5837_read_calibration_data(&bar30_instance->sensor))
    {
        printf("Failed to read calibration data\n");
        return 1;
    }
    
    return 0;
}

int bar30_stop(bar30_t *bar30_instance)
{   

    if (bar30_instance->sensor.pigpiod_instance_handle >= 0)
    {
        pigpio_stop(bar30_instance->sensor.pigpiod_instance_handle); // Stop pigpio daemon
        bar30_instance->sensor.pigpiod_instance_handle = -1; // Reset handle
    }
    return 0;
}




int bar30_read(bar30_t *bar30_instance)
{

    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return 1; // Error reading sensor
    }
    //bar30_t bar30 = *bar30_instance; // Use the provided instance
    uint16_t wait_us = ms5837_start_conversion(&bar30_instance->sensor, SENSOR_PRESSURE, OSR_512);
    usleep(wait_us); // Wait for twice the conversion time
    int result = ms5837_read_conversion(&bar30_instance->sensor);
    if (result == 0)
    {
        return 2; 
    }

    wait_us = ms5837_start_conversion(&bar30_instance->sensor, SENSOR_TEMPERATURE, OSR_512);
    usleep(wait_us); // Wait for twice the conversion time
    result = ms5837_read_conversion(&bar30_instance->sensor);
    if (result == 0)
    {
        return 3; 
    }

    ms5837_calculate(&bar30_instance->sensor);



    return 0; 
}

int bar30_pressure_mbar(bar30_t *bar30_instance, float *pressure_mbar)
{

    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return 1; // Error reading sensor
    }


    if (pressure_mbar == NULL)
    {
        return 2; 
    }

    *pressure_mbar = ms5837_pressure_mbar(&bar30_instance->sensor); // Get pressure in mbar
    return 0; 
}

int bar30_temperature_celcius(bar30_t *bar30_instance, float *temperature_c)
{

    *temperature_c = ms5837_temperature_celcius(&bar30_instance->sensor); // Get temperature in Celsius
    return 0; 
}

int bar30_depth_meters(bar30_t *bar30_instance, float *depth_meters)
{
    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return 1; // Error reading sensor
    }


    float pressure_mbar = 0.0f;
    if (bar30_pressure_mbar(bar30_instance, &pressure_mbar) != 0) {
        return 3; // Error reading pressure
    }

    float pressure_Pa = pressure_mbar * UNITS_Pa; // Convert mbar to Pa

    BAR30_WATER_TYPE water_type = BAR_30_SALTWATER; // Default to freshwater
    if (bar30_get_water_type(bar30_instance, &water_type) != 0) {
        return 4; // Error getting water type
    }

    int density = (water_type == BAR_30_FRESHWATER) ? DENSITY_FRESHWATER : DENSITY_SALTWATER;

    *depth_meters = ((pressure_Pa-ALTITUDE_BASE_PRESSURE_PA) / (density * GRAVITY_ACCELERATION)); // Convert Pa to meters

    return 0; 
}

int bar30_altitude_meters(bar30_t *bar30_instance, float *altitude_meters)
{
    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return 1; // Error reading sensor
    }

    if (altitude_meters == NULL)
    {
        return 2; 
    }

    float pressure_mbar = 0.0f;
    if (bar30_pressure_mbar(bar30_instance, &pressure_mbar) != 0) {
        return 3; // Error reading pressure
    }
    float pressure_Pa = pressure_mbar * UNITS_Pa; // Convert mbar to Pa
    // Calculate altitude using the barometric formula
    *altitude_meters = ALTITUDE_COEFFICIENT * (1.0f - powf((pressure_Pa / ALTITUDE_BASE_PRESSURE_PA), ALTITUDE_EXPONENT));
    return 0; 
}

int bar30_set_water_type(bar30_t *bar30_instance, BAR30_WATER_TYPE water_type)
{
    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return 1; // Error setting water type
    }

    if (water_type != BAR_30_FRESHWATER && water_type != BAR_30_SALTWATER) {
        printf("Error: Invalid water type\n");
        return 2; // Invalid water type
    }

    bar30_instance->water_type = water_type; // Set the water type in the sensor object
    return 0; 
}

int bar30_get_water_type(bar30_t *bar30_instance, BAR30_WATER_TYPE *water_type)
{
    if (bar30_instance == NULL || water_type == NULL) {
        printf("Error: bar30_instance or water_type is NULL\n");
        return 1; // Error getting water type
    }

    *water_type = bar30_instance->water_type; // Get the water type from the sensor object
    return 0; 
}




void bar30_i2c_read(int16_t pigpiod_instance_handle, uint16_t i2c_bus, uint8_t address, uint8_t command, uint8_t *data, uint8_t num_bytes)
{
    int handle = i2c_open(pigpiod_instance_handle, i2c_bus, address, 0); // Open I2C device with the specified address

    if (handle < 0)
    {
        char *error_message = pigpio_error(handle);
        printf("Device open failed. Error %d: %s\n", address, error_message);
        printf("Pigpiod handle: %d, i2c_bus: %d, address: 0x%2X, command: 0x%2X\n", pigpiod_instance_handle, i2c_bus, address, command);
        return;
    }

    i2c_write_byte(pigpiod_instance_handle, handle, command); // Write the command to the device
    int result = i2c_read_device(pigpiod_instance_handle, handle, (char*)data, num_bytes);
    if (result < 0) {
        char *error_message = pigpio_error(result);
        printf("Read Failed. Error %d: %s\n", result, error_message);
        printf("Pigpiod handle: %d, i2c_bus: %d, address: 0x%2X, command: 0x%2X\n", pigpiod_instance_handle, i2c_bus, address, command);
    }

    i2c_close(pigpiod_instance_handle, handle); // Close the I2C device
    
}

void bar30_i2c_write(int16_t pigpiod_instance_handle, uint16_t i2c_bus, uint8_t address, uint8_t command, uint8_t*, uint8_t)
{
    int handle = i2c_open(pigpiod_instance_handle, i2c_bus, address, 0); // Open I2C device with the specified address
    if (handle < 0)
    {
        char *error_message = pigpio_error(handle);
        printf("Device open failed. Error %d: %s\n", address, error_message);
        printf("Pigpiod handle: %d, i2c_bus: %d, address: 0x%2X, command: 0x%2X\n", pigpiod_instance_handle, i2c_bus, address, command);
        return;
    }


    int result = i2c_write_byte(pigpiod_instance_handle, handle, command);
    if (result < 0)
    {
        char *error_message = pigpio_error(result);
        printf("Error: I2C write failed with error %d: %s\n", result, error_message);
        printf("Pigpiod handle: %d, i2c_bus: %d, address: 0x%2X, command: 0x%2X\n", pigpiod_instance_handle, i2c_bus, address, command);
    }

    i2c_close(pigpiod_instance_handle, handle); // Close the I2C device
}


void bar30_print_calibration_data(bar30_t *bar30_instance)
{
    if (bar30_instance == NULL) {
        printf("Error: bar30_instance is NULL\n");
        return; // Cannot print calibration data
    }

    ms5837_t *sensor = &bar30_instance->sensor;
    if (!sensor->calibration_loaded) {
        printf("Calibration data not loaded.\n");
        return;
    }

    printf("Calibration Data:\n");
    for (int i = 0; i < NUM_CALIBRATION_VARIABLES; i++) {
        printf("C%d: 0x%2X\n", i, sensor->calibration_data[i]);
    }
}
