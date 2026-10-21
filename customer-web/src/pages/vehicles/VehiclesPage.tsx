import React, { useState, useEffect } from 'react';
import {
  Car,
  Plus,
  Trash2,
  Upload,
  CheckCircle,
  AlertCircle,
  FileText,
  ShieldCheck,
} from 'lucide-react';
import { api } from '../../services/api';
import type { Vehicle, VehicleType } from '../../types';
import { Modal } from '../../components/ui/Modal';
import { compressImage } from '../../services/imageCompression';

export const VehiclesPage: React.FC = () => {
  const [vehicles, setVehicles] = useState<Vehicle[]>([]);
  const [loading, setLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);

  // Add Vehicle Modal State
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [vehicleNumber, setVehicleNumber] = useState('');
  const [vehicleType, setVehicleType] = useState<VehicleType>('five_seater');
  const [model, setModel] = useState('');
  const [rcFile, setRcFile] = useState<File | null>(null);
  const [vehiclePhotoFile, setVehiclePhotoFile] = useState<File | null>(null);
  const [rcPreview, setRcPreview] = useState<string | null>(null);
  const [vehiclePhotoPreview, setVehiclePhotoPreview] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [compressionInfo, setCompressionInfo] = useState<string | null>(null);

  // Delete Confirmation State
  const [vehicleToDelete, setVehicleToDelete] = useState<Vehicle | null>(null);
  const [deleting, setDeleting] = useState(false);

  const loadVehicles = async () => {
    try {
      setLoading(true);
      setErrorMessage(null);
      const items = await api.getVehicles();
      setVehicles(items);
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to load vehicles');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadVehicles();
  }, []);

  // Handle RC image select with compression
  const handleRCSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      const result = await compressImage(file, 'rcDocument');
      setRcFile(result.file);
      setRcPreview(result.previewUrl);
      if (result.reductionPercentage > 0) {
        setCompressionInfo(`RC Document compressed by ${result.reductionPercentage}%`);
      }
    } catch {
      setRcFile(file);
      setRcPreview(URL.createObjectURL(file));
    }
  };

  // Handle Vehicle Photo select with compression
  const handleVehiclePhotoSelect = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    try {
      const result = await compressImage(file, 'vehicle');
      setVehiclePhotoFile(result.file);
      setVehiclePhotoPreview(result.previewUrl);
      if (result.reductionPercentage > 0) {
        setCompressionInfo(`Vehicle Photo compressed by ${result.reductionPercentage}%`);
      }
    } catch {
      setVehiclePhotoFile(file);
      setVehiclePhotoPreview(URL.createObjectURL(file));
    }
  };

  const handleAddVehicle = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!vehicleNumber.trim()) {
      setErrorMessage('Please enter the vehicle registration number.');
      return;
    }
    if (!model.trim()) {
      setErrorMessage('Please enter the vehicle model.');
      return;
    }

    try {
      setSubmitting(true);
      setErrorMessage(null);

      // 1. Create vehicle record in DB
      const res = await api.addVehicle({
        vehicle_number: vehicleNumber.trim().toUpperCase(),
        vehicle_type: vehicleType,
        model: model.trim(),
      });

      const newVehicleId = res.vehicle_id;

      // 2. Upload compressed images if selected
      if (rcFile && newVehicleId) {
        try {
          await api.uploadVehicleImage(newVehicleId, 'rc', rcFile);
        } catch (err) {
          console.error('RC upload failed:', err);
        }
      }

      if (vehiclePhotoFile && newVehicleId) {
        try {
          await api.uploadVehicleImage(newVehicleId, 'vehicle', vehiclePhotoFile);
        } catch (err) {
          console.error('Vehicle image upload failed:', err);
        }
      }

      setSuccessMessage('Vehicle added successfully!');
      setTimeout(() => setSuccessMessage(null), 3000);

      // Reset form
      setVehicleNumber('');
      setModel('');
      setVehicleType('five_seater');
      setRcFile(null);
      setVehiclePhotoFile(null);
      setRcPreview(null);
      setVehiclePhotoPreview(null);
      setCompressionInfo(null);
      setIsAddModalOpen(false);

      await loadVehicles();
    } catch (err: any) {
      setErrorMessage(err.message || 'Failed to add vehicle');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteVehicle = async () => {
    if (!vehicleToDelete) return;

    try {
      setDeleting(true);
      await api.deleteVehicle(vehicleToDelete.id);
      setSuccessMessage(`${vehicleToDelete.model} deleted from database successfully.`);
      setTimeout(() => setSuccessMessage(null), 3000);
      setVehicleToDelete(null);
      await loadVehicles();
    } catch (err: any) {
      const msg = err.message || '';
      if (
        msg.includes('foreign key') ||
        msg.includes('23503') ||
        msg.includes('violates') ||
        msg.includes('existing bookings')
      ) {
        setErrorMessage('You cannot delete this vehicle because it has existing bookings.');
      } else {
        setErrorMessage(msg || 'Failed to delete vehicle');
      }
    } finally {
      setDeleting(false);
    }
  };

  const getTypeLabel = (type: string) => {
    switch (type) {
      case 'two_wheeler':
        return '2-Seater (Two-Wheeler)';
      case 'five_seater':
        return '5-Seater Car';
      case 'seven_seater':
        return '7-Seater Car';
      default:
        return type;
    }
  };

  return (
    <div className="animate-fade-in" style={{ padding: '1.5rem 0' }}>
      <div className="app-container">
        {/* Header */}
        <div
          style={{
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: '1.5rem',
            flexWrap: 'wrap',
            gap: '1rem',
          }}
        >
          <div>
            <h1 style={{ fontSize: '1.75rem', fontWeight: 800, color: 'var(--navy)', marginBottom: '0.25rem' }}>
              My Registered Vehicles
            </h1>
            <p style={{ color: 'var(--grey)', fontSize: '0.95rem' }}>
              Manage your personal vehicles used for offering rides.
            </p>
          </div>

          <button
            type="button"
            className="btn btn-primary"
            onClick={() => setIsAddModalOpen(true)}
          >
            <Plus size={18} />
            Add Vehicle
          </button>
        </div>

        {/* Success Alert */}
        {successMessage && (
          <div
            style={{
              background: 'var(--emerald-bg)',
              color: 'var(--green)',
              padding: '0.85rem 1rem',
              borderRadius: 'var(--radius-md)',
              marginBottom: '1.25rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              fontWeight: 500,
            }}
          >
            <CheckCircle size={18} />
            <span>{successMessage}</span>
          </div>
        )}

        {/* Error Alert */}
        {errorMessage && (
          <div
            style={{
              background: 'var(--red-bg)',
              color: 'var(--red)',
              padding: '0.85rem 1rem',
              borderRadius: 'var(--radius-md)',
              marginBottom: '1.25rem',
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
              fontWeight: 500,
            }}
          >
            <AlertCircle size={18} />
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Vehicle List */}
        {loading ? (
          <div style={{ textAlign: 'center', padding: '4rem 0', color: 'var(--grey)' }}>
            Loading your vehicles...
          </div>
        ) : vehicles.length > 0 ? (
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(320px, 1fr))',
              gap: '1.25rem',
            }}
          >
            {vehicles.map((v) => (
              <div
                key={v.id}
                className="card card-hover"
                style={{
                  display: 'flex',
                  flexDirection: 'column',
                  justifyContent: 'space-between',
                  gap: '1rem',
                  border: '1.5px solid var(--grey-border)',
                }}
              >
                <div>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '0.75rem' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                      <div
                        style={{
                          width: 44,
                          height: 44,
                          borderRadius: 'var(--radius-lg)',
                          background: 'var(--bg-header)',
                          color: 'var(--blue)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                        }}
                      >
                        <Car size={24} />
                      </div>
                      <div>
                        <h3 style={{ fontSize: '1.15rem', fontWeight: 700, color: 'var(--navy)' }}>
                          {v.model}
                        </h3>
                        <span style={{ fontSize: '0.85rem', color: 'var(--grey)', fontWeight: 600 }}>
                          {v.vehicle_number}
                        </span>
                      </div>
                    </div>

                    <span className="badge badge-blue">
                      {getTypeLabel(v.vehicle_type)}
                    </span>
                  </div>

                  {/* Vehicle Image if available */}
                  {v.vehicle_image_url && (
                    <div style={{ height: 140, borderRadius: 'var(--radius-md)', overflow: 'hidden', marginBottom: '0.75rem' }}>
                      <img
                        src={v.vehicle_image_url}
                        alt={v.model}
                        style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                      />
                    </div>
                  )}

                  <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginTop: '0.5rem' }}>
                    {v.is_verified && (
                      <span className="badge badge-green" style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                        <ShieldCheck size={12} />
                        Verified
                      </span>
                    )}
                    {v.rc_image_url && (
                      <span className="badge badge-grey" style={{ display: 'flex', alignItems: 'center', gap: '0.25rem' }}>
                        <FileText size={12} />
                        RC Document Uploaded
                      </span>
                    )}
                  </div>
                </div>

                {/* Delete Vehicle Option Button */}
                <div style={{ borderTop: '1px solid var(--grey-border)', paddingTop: '0.75rem', display: 'flex', justifyContent: 'flex-end' }}>
                  <button
                    type="button"
                    onClick={() => setVehicleToDelete(v)}
                    className="btn btn-danger"
                    style={{ padding: '0.4rem 0.85rem', fontSize: '0.85rem' }}
                  >
                    <Trash2 size={16} />
                    Delete Vehicle
                  </button>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div
            className="card"
            style={{
              textAlign: 'center',
              padding: '4rem 1.5rem',
              border: '1.5px dashed var(--grey-border)',
              background: '#ffffff',
            }}
          >
            <div
              style={{
                width: 60,
                height: 60,
                borderRadius: '50%',
                background: 'var(--bg-header)',
                color: 'var(--blue)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                margin: '0 auto 1.25rem',
              }}
            >
              <Car size={32} />
            </div>
            <h3 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--navy)', marginBottom: '0.5rem' }}>
              No vehicles added yet
            </h3>
            <p style={{ color: 'var(--grey)', fontSize: '0.9rem', maxWidth: 420, margin: '0 auto 1.5rem' }}>
              Add your vehicle details to start offering rides and sharing commute costs with co-passengers.
            </p>
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => setIsAddModalOpen(true)}
            >
              <Plus size={18} />
              Add Your First Vehicle
            </button>
          </div>
        )}

        {/* Add Vehicle Modal */}
        <Modal
          isOpen={isAddModalOpen}
          onClose={() => setIsAddModalOpen(false)}
          title="Add New Vehicle"
          maxWidth="560px"
        >
          <form onSubmit={handleAddVehicle}>
            {compressionInfo && (
              <div
                style={{
                  background: 'var(--bg-header)',
                  color: 'var(--blue)',
                  padding: '0.5rem 0.75rem',
                  borderRadius: 'var(--radius-md)',
                  fontSize: '0.8rem',
                  marginBottom: '1rem',
                }}
              >
                ⚡ {compressionInfo}
              </div>
            )}

            {/* Vehicle Number */}
            <div className="form-group">
              <label className="form-label">Vehicle Registration Number</label>
              <input
                type="text"
                placeholder="e.g. TS09AB1234"
                value={vehicleNumber}
                onChange={(e) => setVehicleNumber(e.target.value.toUpperCase())}
                className="input-field"
                required
              />
            </div>

            {/* Vehicle Type */}
            <div className="form-group">
              <label className="form-label">Vehicle Seating Category</label>
              <select
                value={vehicleType}
                onChange={(e) => setVehicleType(e.target.value as VehicleType)}
                className="input-field"
              >
                <option value="two_wheeler">2-Seater / Two-Wheeler (Bike / Scooter)</option>
                <option value="five_seater">5-Seater (Hatchback / Sedan / Compact SUV)</option>
                <option value="seven_seater">7-Seater (MPV / Large SUV)</option>
              </select>
            </div>

            {/* Model */}
            <div className="form-group">
              <label className="form-label">Vehicle Make & Model</label>
              <input
                type="text"
                placeholder="e.g. Hyundai Creta, Honda City"
                value={model}
                onChange={(e) => setModel(e.target.value)}
                className="input-field"
                required
              />
            </div>

            {/* RC Document Photo Upload */}
            <div className="form-group">
              <label className="form-label">Registration Certificate (RC) Photo</label>
              <div
                style={{
                  border: '1.5px dashed var(--grey-border)',
                  borderRadius: 'var(--radius-md)',
                  padding: '1rem',
                  textAlign: 'center',
                  background: 'var(--bg)',
                  cursor: 'pointer',
                  position: 'relative',
                }}
              >
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleRCSelect}
                  style={{
                    position: 'absolute',
                    inset: 0,
                    opacity: 0,
                    cursor: 'pointer',
                  }}
                />
                {rcPreview ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                    <img
                      src={rcPreview}
                      alt="RC Preview"
                      style={{ width: 48, height: 48, borderRadius: 'var(--radius-sm)', objectFit: 'cover' }}
                    />
                    <div style={{ textAlign: 'left', fontSize: '0.85rem' }}>
                      <span style={{ fontWeight: 600, color: 'var(--navy)' }}>RC Image Selected</span>
                      <p style={{ color: 'var(--grey)', fontSize: '0.75rem' }}>Click to change</p>
                    </div>
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.35rem' }}>
                    <Upload size={20} color="var(--blue)" />
                    <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--navy)' }}>
                      Upload RC Photo
                    </span>
                    <span style={{ fontSize: '0.75rem', color: 'var(--grey)' }}>Auto-compressed for fast upload</span>
                  </div>
                )}
              </div>
            </div>

            {/* Vehicle Photo Upload */}
            <div className="form-group">
              <label className="form-label">Vehicle Photo</label>
              <div
                style={{
                  border: '1.5px dashed var(--grey-border)',
                  borderRadius: 'var(--radius-md)',
                  padding: '1rem',
                  textAlign: 'center',
                  background: 'var(--bg)',
                  cursor: 'pointer',
                  position: 'relative',
                }}
              >
                <input
                  type="file"
                  accept="image/*"
                  onChange={handleVehiclePhotoSelect}
                  style={{
                    position: 'absolute',
                    inset: 0,
                    opacity: 0,
                    cursor: 'pointer',
                  }}
                />
                {vehiclePhotoPreview ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
                    <img
                      src={vehiclePhotoPreview}
                      alt="Vehicle Preview"
                      style={{ width: 48, height: 48, borderRadius: 'var(--radius-sm)', objectFit: 'cover' }}
                    />
                    <div style={{ textAlign: 'left', fontSize: '0.85rem' }}>
                      <span style={{ fontWeight: 600, color: 'var(--navy)' }}>Vehicle Photo Selected</span>
                      <p style={{ color: 'var(--grey)', fontSize: '0.75rem' }}>Click to change</p>
                    </div>
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '0.35rem' }}>
                    <Car size={20} color="var(--green)" />
                    <span style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--navy)' }}>
                      Upload Vehicle Photo
                    </span>
                    <span style={{ fontSize: '0.75rem', color: 'var(--grey)' }}>Auto-compressed for fast upload</span>
                  </div>
                )}
              </div>
            </div>

            <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem', marginTop: '1.5rem' }}>
              <button
                type="button"
                onClick={() => setIsAddModalOpen(false)}
                className="btn btn-outline"
                disabled={submitting}
              >
                Cancel
              </button>
              <button
                type="submit"
                className="btn btn-primary"
                disabled={submitting}
              >
                {submitting ? 'Saving Vehicle...' : 'Save Vehicle'}
              </button>
            </div>
          </form>
        </Modal>

        {/* Delete Confirmation Modal */}
        <Modal
          isOpen={!!vehicleToDelete}
          onClose={() => setVehicleToDelete(null)}
          title="Delete Vehicle?"
          maxWidth="460px"
        >
          {vehicleToDelete && (
            <div>
              <p style={{ color: 'var(--navy)', marginBottom: '1rem', fontSize: '0.95rem' }}>
                Are you sure you want to delete <strong>{vehicleToDelete.model}</strong> ({vehicleToDelete.vehicle_number})?
              </p>
              <p style={{ color: 'var(--grey)', fontSize: '0.875rem', marginBottom: '1.5rem' }}>
                This vehicle will be permanently removed from your account and the database. Any published rides associated with it should be completed or cancelled first.
              </p>
              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '0.75rem' }}>
                <button
                  type="button"
                  onClick={() => setVehicleToDelete(null)}
                  className="btn btn-outline"
                  disabled={deleting}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  onClick={handleDeleteVehicle}
                  className="btn btn-danger"
                  disabled={deleting}
                >
                  {deleting ? 'Deleting...' : 'Delete Vehicle'}
                </button>
              </div>
            </div>
          )}
        </Modal>
      </div>
    </div>
  );
};
