#include "bar30.h"

#include <stdio.h>
#include <time.h>

int main()
{
    bar30_t bar30_instance = { 0 };

    bar30_t *bar30_ptr = &bar30_instance;
    uint16_t i2c_bus = 1; // Set your I2C bus number here
    // Initialize the BAR30 sensor
    if (bar30_init(&bar30_instance, i2c_bus, false) != 0) {
        return 1; // Initialization failed
    }

    float pressure_mbar = 0.0f;
    float temperature_c = 0.0f;
    //float altitude_meters = 0.0f;
    float depth_meters = 0.0f;
    //bar30_print_calibration_data(bar30_ptr);
    // Read pressure and temperature
    if (bar30_read(bar30_ptr) != 0) {
        bar30_stop(bar30_ptr); // Cleanup on error
        return 2; // Read failed
    }



    bar30_pressure_mbar(bar30_ptr, &pressure_mbar);
    bar30_temperature_celcius(bar30_ptr, &temperature_c);
    
    bar30_depth_meters(bar30_ptr, &depth_meters);


    time_t current_time = time(NULL);
    struct tm *tm_info = localtime(&current_time);
    char time_buffer[26];
    strftime(time_buffer, sizeof(time_buffer), "%Y-%m-%d_%H:%M:%S", tm_info);
    
    // Print the results
    printf("%s %.2f %.2f\n", time_buffer, depth_meters, temperature_c);

    // Stop the sensor before exiting
    bar30_stop(bar30_ptr);
    
    return 0; // Success
}
