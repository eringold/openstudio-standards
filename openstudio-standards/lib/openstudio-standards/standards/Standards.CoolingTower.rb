
# A variety of cooling tower methods that are the same regardless of type.
# These methods are available to CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, and CoolingTowerVariableSpeed
module CoolingTower

  # Set the cooling tower fan power such that the tower
  # hits the minimum performance (gpm/hp) specified by the standard.
  # Note that in this case hp is motor nameplate hp, per 90.1.
  # This method assumes that the fan brake horsepower is 90%
  # of the motor nameplate hp.
  # This method determines the minimum motor efficiency
  # for the nameplate motor hp and sets the actual
  # fan power by multiplying the brake horsepower
  # by the efficiency.  Thus the fan power used as
  # an input to the simulation divided by the design flow
  # rate will not (and should not) 
  # exactly equal the minimum tower performance.
  #
  # @param standard [String] the target standard
  # @return [Bool] true if successful, false if not
  def set_minimum_power_per_flow(standard)
    
    # Get the design water flow rate
    design_water_flow_m3_per_s = nil
    if self.designWaterFlowRate.is_initialized
      design_water_flow_m3_per_s = self.designWaterFlowRate.get
    elsif self.autosizedDesignWaterFlowRate.is_initialized
      design_water_flow_m3_per_s = self.autosizedDesignWaterFlowRate.get
    else
      OpenStudio::logFree(OpenStudio::Warn, 'openstudio.standards.CoolingTower', "For #{self.name} design water flow rate is not available, cannot apply efficiency standard.")
      return false
    end    
    design_water_flow_gpm = OpenStudio.convert(design_water_flow_m3_per_s,'m^3/s','gal/min').get    
    
    # Get the table of cooling tower efficiencies
    heat_rejection = $os_standards['heat_rejection']

    # Define the criteria to find the cooling tower properties
    # in the hvac standards data set.
    search_criteria = {}
    search_criteria['template'] = standard
    
    # By definition cooling towers in E+ are open.
    # Closed cooling towers are the fluidcooler objects.
    search_criteria['equipment_type'] = 'Open Cooling Tower'
    
    # TODO Standards replace this with a mechanism to store this
    # data in the cooling tower object itself.
    # For now, retrieve the fan type from the name
    name = self.name.get
    fan_type = nil
    if name.include?('Centrifugal')
      fan_type = 'Centrifugal'
    elsif name.include?('Propeller or Axial')
      fan_type = 'Propeller or Axial'
    end
    unless fan_type.nil?
      search_criteria['fan_type'] = fan_type
    end

    # 90.1 6.5.5.3 Limit on Centrifugal Fan
    # Open Circuit Cooling Towers.  
    case standard
    when '90.1-2010', '90.1-2013'
      if fan_type == 'Centrifugal'
        gpm_limit = 1100
        if design_water_flow_gpm >= gpm_limit
          fan_type = 'Propeller or Axial'
          search_criteria['fan_type'] = fan_type
          OpenStudio::logFree(OpenStudio::Warn, "openstudio.standards.CoolingTower", "For #{self.name}, the design flow rate of #{design_water_flow_gpm.round} gpm is higher than the limit of #{gpm_limit.round} gpm for open centrifugal towers per 6.5.5.3.  This tower must meet the minimum performance of #{fan_type} instead.")
        end
      end
    end

    # Get the cooling tower properties
    ct_props = self.model.find_object(heat_rejection, search_criteria)
    if !ct_props
      OpenStudio::logFree(OpenStudio::Warn, "openstudio.standards.CoolingTower", "For #{self.name}, cannot find heat rejection properties, cannot apply standard efficiencies or curves.")
      return false
    end    

    # Get cooling tower efficiency
    min_gpm_per_hp = ct_props['minimum_performance']
    OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.CoolingTower", "For #{self.name}, design water flow = #{design_water_flow_gpm.round} gpm, minimum performance = #{min_gpm_per_hp} gpm/hp (nameplate).")
    
    # Calculate the allowed fan brake horsepower
    # per method used in PNNL prototype buildings.
    # Assumes that the fan brake horsepower is 90%
    # of the fan nameplate rated motor power.
    fan_motor_nameplate_hp = design_water_flow_gpm / min_gpm_per_hp
    fan_bhp = 0.9 * fan_motor_nameplate_hp
    
    # Lookup the minimum motor efficiency
    fan_motor_eff = 0.85
    motors = $os_standards["motors"]
    
    # Assuming all fan motors are 4-pole Enclosed
    search_criteria = {
      "template" => standard,
      "number_of_poles" => 4.0,
      "type" => "Enclosed",
    }
    
    motor_properties = self.model.find_object(motors, search_criteria, fan_motor_nameplate_hp)
    if motor_properties.nil?
      OpenStudio::logFree(OpenStudio::Error, "openstudio.standards.CoolingTower", "For #{self.name}, could not find motor properties using search criteria: #{search_criteria}, motor_hp = #{motor_hp} hp.")
      return false
    end
 
    fan_motor_eff = motor_properties["nominal_full_load_efficiency"]  
    nominal_hp = motor_properties["maximum_capacity"].to_f.round(1)
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end    
    
    # Calculate the fan motor power
    fan_motor_actual_power_hp = fan_bhp / fan_motor_eff
    # Convert to W
    fan_motor_actual_power_w = fan_motor_actual_power_hp * 745.7 # 745.7 W/HP
    
    OpenStudio::logFree(OpenStudio::Info, "openstudio.standards.CoolingTower", "For #{self.name}, allowed fan motor nameplate hp = #{fan_motor_nameplate_hp.round(1)} hp, fan brake horsepower = #{fan_bhp.round(1)}, and fan motor actual power = #{fan_motor_actual_power_hp.round(1)} hp (#{fan_motor_actual_power_w.round} W) at #{fan_motor_eff} motor efficiency.")
    
    # Append the efficiency to the name
    self.setName("#{self.name} #{min_gpm_per_hp.round(1)} gpm/hp")
    
    # Hard size the design fan power.
    # Leave the water flow and air flow autosized.
    if self.to_CoolingTowerSingleSpeed.is_initialized
      self.setFanPoweratDesignAirFlowRate(fan_motor_actual_power_w)
    elsif self.to_CoolingTowerTwoSpeed.is_initialized
      self.setHighFanSpeedFanPower(fan_motor_actual_power_w)
      self.setLowFanSpeedFanPower(0.3 * fan_motor_actual_power_w)
    elsif self.to_CoolingTowerVariableSpeed.is_initialized
      self.setDesignFanPower(fan_motor_actual_power_w)
    end

    return true
    
  end

end