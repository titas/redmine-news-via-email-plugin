class AddDeployedToChangesets < ActiveRecord::Migration

  def self.up
    add_column :changesets, :deployed, :boolean, :default => false
  end

  def self.down
    remove_column :changesets, :deployed
  end
end
