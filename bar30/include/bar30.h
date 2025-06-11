#include "ms5837.h"


#ifndef BAR30_H
#define BAR30_H

typedef enum {
    BAR_30_FRESHWATER = 0, // Freshwater variant
    BAR_30_SALTWATER,      // Saltwater variant
} BAR30_WATER_TYPE;

typedef struct {
    ms5837_t sensor; // MS5837 sensor object
    BAR30_WATER_TYPE water_type; // Water type (freshwater or saltwater)
} bar30_t;

int bar30_init(bar30_t *bar30_instance, uint16_t i2c_bus, bool verbose);
int bar30_stop(bar30_t *bar30_instance);
int bar30_read(bar30_t *bar30_instance);
int bar30_pressure_mbar(bar30_t *bar30_instance, float *pressure_mbar);
int bar30_temperature_celcius(bar30_t *bar30_instance, float *temperature_c);
int bar30_depth_meters(bar30_t *bar30_instance, float *depth_meters);
int bar30_altitude_meters(bar30_t *bar30_instance, float *altitude_meters);


int bar30_set_water_type(bar30_t *bar30_instance, BAR30_WATER_TYPE water_type);
int bar30_get_water_type(bar30_t *bar30_instance, BAR30_WATER_TYPE *water_type);

void bar30_print_calibration_data(bar30_t *bar30_instance);


#endif // end BAR30_H